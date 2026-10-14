import SwiftUI

extension Person {
    /// Card color from the server's payment state: red overdue, amber due soon, else green.
    var stateColor: Color { statusMeta.isOverdue ? Palette.danger : (statusMeta.isSoonDue ? Palette.warning : Palette.success) }
    var standingOrderCovers: Bool { statusMeta.isActiveStandingOrder && !statusMeta.isOverdue }
}

/// Payment status (start page and member finances): server-computed state, paid-until month, open amount.
struct FinanceStatusCard: View {
    @Environment(AppStore.self) private var store
    let user: User
    let person: Person?
    var showDetails = false
    var onStatusTap: (() -> Void)?

    var body: some View {
        if !user.pays {
            VStack(spacing: 6) {
                Image(systemName: "person.crop.circle").font(.system(size: 28)).foregroundStyle(Palette.textSecondary)
                Text("Benutzerkonto").font(.system(size: 20, weight: .bold)).foregroundStyle(Palette.text)
                Text("Aktives Benutzerkonto (Keine Beitragspflicht)").font(.system(size: 14)).foregroundStyle(Palette.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .card(padding: 22)
        } else if let person {
            PersonStatusHero(person: person, rate: store.data.fees.rate(for: person.effectiveStatus), showDetails: showDetails, onStatusTap: onStatusTap)
        } else {
            Text("Kein Mitgliedseintrag gefunden. Bitte kontaktieren Sie einen Administrator.")
                .font(.system(size: 15))
                .foregroundStyle(Palette.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .card(padding: 22)
        }
    }
}

/// The fee state of one member (web v3.1: .user-finance-hero-card / .member-hero): a round symbol, the state in
/// plain words, "Bezahlt bis", the open amount when overdue and - with `showDetails` - fee and status as two chips
/// side by side. `compact`: the smaller version inside an opened card of the fee list (always shows "Bezahlt bis").
struct PersonStatusHero: View {
    let person: Person
    let rate: Double
    var showDetails = false
    var onStatusTap: (() -> Void)?
    var compact = false

    var body: some View {
        let color = person.stateColor
        let meta = person.statusMeta
        let symbol = meta.isOverdue ? "exclamationmark" : (meta.isSoonDue ? "clock" : "checkmark")
        let shape = RoundedRectangle(cornerRadius: compact ? 20 : 26, style: .continuous)
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                Image(systemName: symbol)
                    .font(.system(size: compact ? 18 : 22, weight: .bold))
                    .foregroundStyle(Color.adaptive(0xFFFFFF, 0x181817))
                    .frame(width: compact ? 42 : 50, height: compact ? 42 : 50)
                    .background(color, in: Circle())
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(meta.text.isEmpty ? String(localized: "Alles in Ordnung") : meta.text)
                        .font(.system(size: compact ? 19 : 21, weight: .bold))
                        .foregroundStyle(color)
                    Group {
                        if !compact && person.standingOrderCovers {
                            Text("Dauerauftrag aktiv")
                        } else {
                            Text("Bezahlt bis ") + Text(Formats.paidUntilMonth(person.paidUntil) ?? String(localized: "Nie")).bold().foregroundColor(Palette.text)
                        }
                    }
                    .font(.system(size: 14))
                    .foregroundStyle(Palette.textSecondary)
                }
            }
            .accessibilityElement(children: .combine)
            if meta.isOverdue && person.overdueAmount > 0 {
                HStack {
                    Text("Offener Betrag").font(.system(size: 14, weight: .semibold))
                    Spacer()
                    Text(Formats.money(person.overdueAmount)).font(.system(size: 19, weight: .bold))
                }
                .foregroundStyle(color)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(color.opacity(0.09), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .accessibilityElement(children: .combine)
            }
            if showDetails {
                HStack(spacing: 8) {
                    chip {
                        (Text(Formats.money(rate)).bold().foregroundColor(Palette.text) + Text(" im Monat"))
                            .font(.system(size: 14))
                            .foregroundStyle(Palette.textSecondary)
                            .lineLimit(1)
                    }
                    // Plain status name: the emoji of the label made it too wide
                    Button { onStatusTap?() } label: {
                        chip {
                            Text(MemberStatus.name(person.effectiveStatus)).font(.system(size: 14, weight: .semibold)).foregroundStyle(Palette.text).lineLimit(1)
                            if onStatusTap != nil {
                                Image(systemName: "chevron.right").font(.system(size: 11, weight: .bold)).foregroundStyle(Palette.textSecondary)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(onStatusTap == nil)
                    .accessibilityHint(onStatusTap == nil ? "" : "Statusänderung beantragen")
                }
            }
        }
        .padding(compact ? 16 : 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            shape.fill(Palette.surface)
                .overlay(RadialGradient(colors: [color.opacity(0.13), .clear], center: .topTrailing, startRadius: 0, endRadius: 320).clipShape(shape))
        }
        .overlay(shape.strokeBorder(color.opacity(0.26), lineWidth: 1))
        .shadow(color: Palette.shadow, radius: 4, y: 1)
    }

    /// A chip of the status card: fee per month or the status (tap to request a change).
    private func chip<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: 4) { content() }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .background(Palette.surfaceAlt, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Palette.borderLight, lineWidth: 1))
    }
}

/// "Verlauf": payments and status changes on a line, newest first.
struct FinanceTimeline: View {
    let person: Person
    /// Status names without emoji (fee list of the treasurers)
    var plainStatus = false

    var body: some View {
        let entries = TimelineEntry.build(for: person)
        if entries.isEmpty {
            Text("Keine Einträge vorhanden.").font(.system(size: 14)).foregroundStyle(Palette.textSecondary)
        } else {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                    HStack(alignment: .top, spacing: 12) {
                        VStack(spacing: 4) {
                            Circle()
                                .fill(isPayment(entry) ? Palette.primary : Palette.indigo)
                                .frame(width: 11, height: 11)
                                .overlay(Circle().strokeBorder(Palette.surface, lineWidth: 2))
                                .padding(.top, 4)
                            if index < entries.count - 1 {
                                Rectangle().fill(Palette.borderLight).frame(width: 2).frame(maxHeight: .infinity)
                            }
                        }
                        .frame(width: 14)
                        VStack(alignment: .leading, spacing: 2) {
                            switch entry.kind {
                            case .payment(let amount, let note):
                                Text("Zahlung: \(Formats.money(amount))").font(.system(size: 15, weight: .semibold)).foregroundStyle(Palette.text)
                                Text("\(note.isEmpty ? String(localized: "Keine Notiz") : note) · \(Formats.shortDay(entry.date))")
                                    .font(.system(size: 13)).foregroundStyle(Palette.textSecondary)
                            case .status(let status):
                                Text("Statusänderung: \(plainStatus ? MemberStatus.name(status) : MemberStatus.label(status))").font(.system(size: 15, weight: .semibold)).foregroundStyle(Palette.text)
                                Text("Gültig ab \(Formats.shortDay(entry.date))").font(.system(size: 13)).foregroundStyle(Palette.textSecondary)
                            }
                        }
                        .padding(.bottom, index < entries.count - 1 ? 14 : 0)
                        .accessibilityElement(children: .combine)
                    }
                }
            }
        }
    }

    private func isPayment(_ entry: TimelineEntry) -> Bool {
        if case .payment = entry.kind { return true }
        return false
    }
}

/// Request state chip: in review, approved, rejected.
struct RequestStateChip: View {
    let status: String

    var body: some View {
        switch status {
        case "approved": StatusPill(text: String(localized: "Genehmigt"), color: Palette.success, systemImage: "checkmark")
        case "rejected": StatusPill(text: String(localized: "Abgelehnt"), color: Palette.danger, systemImage: "xmark")
        default: StatusPill(text: String(localized: "In Prüfung"), color: Palette.warning, systemImage: "hourglass")
        }
    }
}

extension FinanceRequest {
    var icon: String {
        switch type {
        case "status": return "arrow.triangle.2.circlepath"
        case "expense": return "creditcard"
        case "standing_order": return "repeat"
        default: return "eurosign.circle"
        }
    }

    var title: String {
        switch type {
        case "status": return String(localized: "Statuswechsel")
        case "expense": return String(localized: "Ausgabe")
        case "standing_order": return String(localized: "Dauerauftrag")
        default: return String(localized: "Zahlung")
        }
    }

    /// Detail chips in the web app's order: amount, date, new status, note, description, receipts.
    var detailChips: [String] {
        var chips: [String] = []
        if data["amount"] != nil { chips.append(Formats.money(amount)) }
        if let date = field("date"), !date.isEmpty { chips.append(Formats.shortDay(date)) }
        if let status = field("newStatus"), !status.isEmpty { chips.append(MemberStatus.label(status)) }
        if let note = field("note"), !note.isEmpty { chips.append(note) }
        if let description = field("description"), !description.isEmpty { chips.append(description) }
        let count = receipts.count
        if count > 0 { chips.append(count == 1 ? String(localized: "1 Beleg") : String(localized: "\(count) Belege")) }
        return chips
    }
}
