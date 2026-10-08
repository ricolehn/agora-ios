import SwiftUI

// Requests like the web (beta18) and Android: open requests as a calm list in the style of "Neue Nachrichten"
// (avatar, name, amount, coloured type, text); a tap opens the request in a sheet with all details and the decision.
// Members get three action tiles and "Meine Anfragen" with the state of each request.

extension FinanceRequest {
    /// Colour of the request type: payment green, expense red, status indigo, standing order cyan.
    var color: Color {
        switch type {
        case "expense": return Palette.danger
        case "status": return Color(hex: 0x6366F1)
        case "standing_order": return Color(hex: 0x06B6D4)
        default: return Palette.success
        }
    }

    /// Amount (or the new status) of the request, "/ Monat" for standing orders.
    var amountText: String {
        if type == "status" { return MemberStatus.name(field("newStatus")) }
        let money = Formats.money(amount)
        return type == "standing_order" ? String(localized: "\(money) / Monat") : money
    }

    /// "am 3. Okt. 2026" / "ab 1. Nov. 2026" (status changes and standing orders start on the date).
    var dateLabel: String {
        guard let date = field("date"), !date.isEmpty else { return "" }
        let day = Formats.shortDay(date)
        return type == "status" || type == "standing_order" ? String(localized: "ab \(day)") : String(localized: "am \(day)")
    }

    /// The member's text: purpose of an expense, note of a payment.
    var text: String? { (type == "expense" ? field("description") : field("note")).flatMap(\.nilIfEmpty) }

    var stateText: String {
        switch status {
        case "approved": return String(localized: "Genehmigt")
        case "rejected": return String(localized: "Abgelehnt")
        default: return String(localized: "In Prüfung")
        }
    }

    var stateColor: Color {
        switch status {
        case "approved": return Palette.success
        case "rejected": return Palette.danger
        default: return Palette.warning
        }
    }
}

/// Card head like "Neue Nachrichten": icon tile, title, count badge and an optional "Alle" link.
private struct RequestsHead: View {
    let title: LocalizedStringKey
    let count: Int
    let badge: Color
    var onAll: (() -> Void)?

    var body: some View {
        HStack(spacing: 10) {
            IconTile(systemImage: "doc.text", color: Palette.warning, size: 34)
            Text(title).font(.system(size: 16, weight: .heavy)).foregroundStyle(Palette.text)
            CountBadge(count: count, color: badge)
            Spacer(minLength: 0)
            if let onAll {
                Button(action: onAll) {
                    HStack(spacing: 2) {
                        Text("Alle")
                        Image(systemName: "chevron.right").font(.system(size: 11, weight: .bold))
                    }
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Palette.primary)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 10)
    }
}

/// Coloured dot + caps text (request type, or the state of an own request), paperclip when receipts are attached.
private struct DotLabel: View {
    let text: String
    let color: Color
    let withReceipt: Bool

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(text).font(.agoraCaps).textCase(.uppercase).tracking(0.6).foregroundStyle(Palette.textSecondary).lineLimit(1)
            if withReceipt { Image(systemName: "paperclip").font(.system(size: 11, weight: .bold)).foregroundStyle(Palette.textSecondary) }
        }
    }
}

/// "Offene Anfragen": on the finances tab all of them, on the start page of treasurers the three newest with "Alle".
struct OpenRequestsCard: View {
    let requests: [FinanceRequest]
    var limit = Int.max
    var onAll: (() -> Void)?
    let onOpen: (FinanceRequest) -> Void

    var body: some View {
        VStack(spacing: 0) {
            RequestsHead(title: "Offene Anfragen", count: requests.count, badge: Palette.warning, onAll: onAll)
            ForEach(requests.prefix(limit)) { request in
                Hairline()
                Button { onOpen(request) } label: { row(request) }
                    .buttonStyle(.pressable)
            }
            if requests.count > limit, let onAll {
                Hairline()
                Button(action: onAll) {
                    Text("+\(requests.count - limit) weitere Anfragen")
                        .font(.system(size: 13)).foregroundStyle(Palette.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.plain)
            }
        }
        .card(padding: 0)
    }

    private func row(_ request: FinanceRequest) -> some View {
        let name = request.personName.nilIfEmpty ?? "–"
        return HStack(spacing: 12) {
            Avatar(userId: request.userId.nilIfEmpty, name: name, size: 44)
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(name).font(.system(size: 15, weight: .heavy)).foregroundStyle(Palette.text).lineLimit(1)
                    Spacer(minLength: 8)
                    Text(request.amountText).font(.system(size: 15, weight: .heavy)).foregroundStyle(Palette.text).lineLimit(1)
                }
                DotLabel(text: request.typeLabel, color: request.color, withReceipt: !request.receipts.isEmpty)
                Text(request.text ?? request.dateLabel).font(.system(size: 14)).foregroundStyle(Palette.textSecondary).lineLimit(1)
            }
            Image(systemName: "chevron.right").font(.system(size: 12, weight: .bold)).foregroundStyle(Palette.textSecondary.opacity(0.6))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// Member finances: what can be submitted, one tile per kind with a short explanation.
struct RequestActions: View {
    let onRequest: (RequestKind) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Anfrage stellen").font(.agoraSection).foregroundStyle(Palette.text).padding(.leading, 2).padding(.top, 6)
            VStack(spacing: 0) {
                ForEach(Array(RequestKind.allCases.enumerated()), id: \.element) { index, kind in
                    if index > 0 { Hairline() }
                    Button { onRequest(kind) } label: {
                        HStack(spacing: 12) {
                            IconTile(systemImage: kind.icon, color: kind.color, size: 40)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(kind.actionTitle).font(.system(size: 15, weight: .bold)).foregroundStyle(Palette.text)
                                Text(kind.actionDescription).font(.system(size: 13)).foregroundStyle(Palette.textSecondary)
                                    .multilineTextAlignment(.leading)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right").font(.system(size: 12, weight: .bold)).foregroundStyle(Palette.textSecondary.opacity(0.6))
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.pressable)
                }
            }
            .card(padding: 0)
        }
    }
}

extension RequestKind {
    var icon: String {
        switch self {
        case .payment: return "eurosign.circle"
        case .expense: return "doc.text"
        case .status: return "arrow.triangle.2.circlepath"
        }
    }

    var color: Color {
        switch self {
        case .payment: return Palette.success
        case .expense: return Palette.danger
        case .status: return Color(hex: 0x6366F1)
        }
    }

    var actionTitle: LocalizedStringKey {
        switch self {
        case .payment: return "Zahlung melden"
        case .expense: return "Ausgabe erstatten lassen"
        case .status: return "Status ändern"
        }
    }

    var actionDescription: LocalizedStringKey {
        switch self {
        case .payment: return "Beitrag, Einzahlung oder Dauerauftrag melden."
        case .expense: return "Auslage mit Beleg zur Erstattung einreichen."
        case .status: return "Änderung des Mitgliedsstatus beantragen."
        }
    }
}

/// "Meine Anfragen": type, amount, state (pending / approved / rejected with reason); five shown + "Alle anzeigen".
struct MyRequestsCard: View {
    let requests: [FinanceRequest]
    let onOpen: (FinanceRequest) -> Void
    @State private var showAll = false
    private let shown = 5

    var body: some View {
        if requests.isEmpty {
            VStack(spacing: 6) {
                Image(systemName: "doc.text").font(.system(size: 22, weight: .semibold)).foregroundStyle(Palette.textSecondary)
                Text("Noch keine Anfragen").font(.system(size: 15, weight: .bold)).foregroundStyle(Palette.text)
                Text("Deine Anfragen und ihr Stand erscheinen hier.").font(.system(size: 13)).foregroundStyle(Palette.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .card(padding: 20)
        } else {
            VStack(spacing: 0) {
                RequestsHead(title: "Meine Anfragen", count: requests.count, badge: Palette.primary)
                ForEach(showAll ? requests : Array(requests.prefix(shown))) { request in
                    Hairline()
                    Button { onOpen(request) } label: { row(request) }
                        .buttonStyle(.pressable)
                }
                if requests.count > shown {
                    Hairline()
                    Button { withAnimation(.snappy) { showAll.toggle() } } label: {
                        Text(showAll ? String(localized: "Weniger anzeigen") : String(localized: "Alle \(requests.count) anzeigen"))
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(Palette.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.plain)
                }
            }
            .card(padding: 0)
        }
    }

    private func row(_ request: FinanceRequest) -> some View {
        let rejected = request.status == "rejected"
        let sent = request.timestamp > 0
            ? " · " + Formats.shortDay(Day.string(Date(timeIntervalSince1970: TimeInterval(request.timestamp) / 1000))) : ""
        return HStack(spacing: 12) {
            Image(systemName: request.icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(request.color)
                .frame(width: 42, height: 42)
                .background(request.color.opacity(0.13), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(request.typeLabel).font(.system(size: 15, weight: .heavy)).foregroundStyle(Palette.text).lineLimit(1)
                    Spacer(minLength: 8)
                    Text(request.amountText).font(.system(size: 15, weight: .heavy)).foregroundStyle(Palette.text).lineLimit(1)
                }
                DotLabel(text: request.stateText + sent, color: request.stateColor, withReceipt: !request.receipts.isEmpty)
                Text(rejected ? String(localized: "Grund: \(request.rejectionReason?.nilIfEmpty ?? "–")") : (request.text ?? request.dateLabel))
                    .font(.system(size: 14))
                    .foregroundStyle(rejected ? Palette.danger : Palette.textSecondary)
                    .lineLimit(1)
            }
            Image(systemName: "chevron.right").font(.system(size: 12, weight: .bold)).foregroundStyle(Palette.textSecondary.opacity(0.6))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// One request with all details: amount hero, sender, purpose / note, date of receipt, state, receipts. Treasurers
/// decide on pending requests here (approve, or reject with an optional reason the member sees).
struct RequestDetailSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(ToastCenter.self) private var toasts
    @Environment(\.dismiss) private var dismiss
    let request: FinanceRequest
    let canDecide: Bool
    var onDecided: () -> Void = {}
    @State private var runner = ActionRunner()
    @State private var rejecting = false
    @State private var reason = ""

    private var decide: Bool { canDecide && request.isPending }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    hero
                    details
                    if !request.receipts.isEmpty {
                        CapsLabel("Belege")
                        ReceiptStrip(files: request.receipts)
                    }
                    if rejecting {
                        VStack(alignment: .leading, spacing: 6) {
                            CapsLabel("Grund für Ablehnung")
                            TextField("Optional – das Mitglied sieht den Grund", text: $reason, axis: .vertical)
                                .lineLimit(2...4)
                                .padding(12)
                                .background(Palette.surfaceAlt, in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: Radius.control, style: .continuous).strokeBorder(Palette.borderLight, lineWidth: 1))
                        }
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }
                }
                .padding(20)
            }
            .background(Palette.background.ignoresSafeArea())
            .safeAreaInset(edge: .bottom) { if decide { actions } }
            .navigationTitle(request.typeLabel)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Fertig") { dismiss() } } }
            .interactiveDismissDisabled(runner.busy)
        }
        .presentationDetents(decide ? [.large] : [.medium, .large])
    }

    /// Amount tinted in the colour of the request type.
    private var hero: some View {
        VStack(spacing: 4) {
            Image(systemName: request.icon).font(.system(size: 18, weight: .semibold)).foregroundStyle(request.color)
            Text(request.amountText).font(.system(size: 30, weight: .heavy)).foregroundStyle(Palette.text)
                .multilineTextAlignment(.center).minimumScaleFactor(0.6)
            if !request.dateLabel.isEmpty {
                Text(request.dateLabel).font(.system(size: 14)).foregroundStyle(Palette.textSecondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .padding(.horizontal, 12)
        .background(request.color.opacity(0.08), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(request.color.opacity(0.22), lineWidth: 1))
        .accessibilityElement(children: .combine)
    }

    private var details: some View {
        var rows: [(icon: String, label: String, value: String, color: Color)] = [
            ("person", String(localized: "Von"), request.personName.nilIfEmpty ?? "–", Palette.text)
        ]
        if let text = request.text {
            rows.append((request.type == "expense" ? "doc.text" : "note.text",
                         request.type == "expense" ? String(localized: "Zweck") : String(localized: "Notiz"), text, Palette.text))
        }
        if request.timestamp > 0 {
            rows.append(("clock", String(localized: "Eingegangen"), Formats.dateTime(millis: request.timestamp), Palette.text))
        }
        if !decide { rows.append(("info.circle", String(localized: "Status"), request.stateText, request.stateColor)) }
        if request.status == "rejected" {
            rows.append(("xmark", String(localized: "Grund"), request.rejectionReason?.nilIfEmpty ?? "–", Palette.danger))
        }
        return VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                if index > 0 { Hairline() }
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: row.icon).font(.system(size: 14, weight: .semibold)).foregroundStyle(Palette.textSecondary)
                        .frame(width: 18).padding(.top, 1)
                    Text(row.label).font(.system(size: 14.5, weight: .semibold)).foregroundStyle(Palette.textSecondary)
                    Spacer(minLength: 12)
                    Text(row.value).font(.system(size: 14.5, weight: .semibold)).foregroundStyle(row.color).multilineTextAlignment(.trailing)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .accessibilityElement(children: .combine)
            }
        }
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Palette.borderLight, lineWidth: 1))
    }

    private var actions: some View {
        HStack(spacing: 10) {
            if rejecting {
                Button("Abbrechen") { withAnimation(.snappy) { rejecting = false } }
                    .buttonStyle(.agoraSecondary)
                Button { reject() } label: { BusyLabel(title: "Ablehnen", busy: runner.busy) }
                    .buttonStyle(.agoraDanger)
            } else {
                Button { withAnimation(.snappy) { rejecting = true } } label: { Label("Ablehnen", systemImage: "xmark") }
                    .buttonStyle(.agoraSecondary(tint: Palette.danger))
                Button { approve() } label: { BusyLabel(title: "Genehmigen", systemImage: "checkmark", busy: runner.busy) }
                    .buttonStyle(.agoraPrimary)
                    .layoutPriority(1)
            }
        }
        .disabled(runner.busy)
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(.bar)
    }

    private func approve() {
        runner.run(toasts, success: String(localized: "Anfrage genehmigt")) {
            try await store.repository.approveRequest(request)
            await store.refreshAll()
            onDecided()
            dismiss()
        }
    }

    private func reject() {
        let text = reason
        runner.run(toasts, success: String(localized: "Anfrage abgelehnt")) {
            try await store.repository.rejectRequest(id: request.id, reason: text)
            await store.refreshAll()
            onDecided()
            dismiss()
        }
    }
}
