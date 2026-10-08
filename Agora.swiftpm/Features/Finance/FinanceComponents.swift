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
                Text("Benutzerkonto").font(.system(size: 20, weight: .heavy)).foregroundStyle(Palette.text)
                Text("Aktives Benutzerkonto (Keine Beitragspflicht)").font(.system(size: 14)).foregroundStyle(Palette.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .card(padding: 22)
        } else if let person {
            let color = person.stateColor
            VStack(spacing: 10) {
                Text(person.statusMeta.text.isEmpty ? String(localized: "Alles in Ordnung") : person.statusMeta.text)
                    .font(.system(size: 22, weight: .heavy))
                    .foregroundStyle(color)
                    .multilineTextAlignment(.center)
                Group {
                    if person.standingOrderCovers {
                        Text("Dauerauftrag aktiv")
                    } else {
                        Text("Bezahlt bis ") + Text(Formats.paidUntilMonth(person.paidUntil) ?? String(localized: "Nie")).bold().foregroundColor(Palette.text)
                    }
                }
                .font(.system(size: 15))
                .foregroundStyle(Palette.textSecondary)
                if person.statusMeta.isOverdue && person.overdueAmount > 0 {
                    VStack(spacing: 4) {
                        CapsLabel("Offener Betrag", color: Palette.danger)
                        Text(Formats.money(person.overdueAmount)).font(.system(size: 26, weight: .heavy)).foregroundStyle(Palette.danger)
                    }
                    .padding(.vertical, 12)
                    .padding(.horizontal, 16)
                    .frame(maxWidth: .infinity)
                    .background(Palette.danger.opacity(0.1), in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: Radius.control, style: .continuous).strokeBorder(Palette.danger.opacity(0.3), lineWidth: 1))
                    .accessibilityElement(children: .combine)
                }
                if showDetails {
                    HStack(spacing: 0) {
                        StatCell(label: "Monatsbeitrag", value: Formats.money(store.data.fees.rate(for: person.effectiveStatus)))
                        Rectangle().fill(Palette.borderLight).frame(width: 1, height: 40)
                        Button { onStatusTap?() } label: {
                            // Plain status name: the emoji of the label made it too wide for the tile
                            StatCell(label: "Status", value: MemberStatus.name(person.effectiveStatus))
                        }
                        .buttonStyle(.plain)
                        .disabled(onStatusTap == nil)
                        .accessibilityHint("Statusänderung beantragen")
                    }
                    .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.nested, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: Radius.nested, style: .continuous).strokeBorder(Palette.borderLight, lineWidth: 1))
                }
            }
            .tintedCard(color, padding: 22)
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
