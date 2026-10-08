import SwiftUI

/// Finanzen tab: treasurers see the treasury, members their own status and requests.
struct FinancesView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        if store.user?.viewsFinances == true {
            TreasurerView()
        } else {
            MemberFinanceView()
        }
    }
}

struct MemberFinanceView: View {
    @Environment(AppStore.self) private var store
    @State private var newRequest: RequestKind?
    @State private var openRequest: FinanceRequest?

    var body: some View {
        TabPage {
            if let user = store.user {
                PageTitle("Finanzen")
                // iPad: status and requests on the left, the history on the right (like the web)
                TwoPane(spacing: 16, leftShare: 0.54) {
                    FinanceStatusCard(user: user, person: store.data.ownPerson, showDetails: true,
                                      onStatusTap: store.data.ownPerson == nil ? nil : { newRequest = .status })
                    // What can be submitted (one tile per kind), then the own requests with their state (web beta18)
                    if store.data.ownPerson != nil {
                        RequestActions { newRequest = $0 }
                    }
                    MyRequestsCard(requests: store.data.ownRequests) { openRequest = $0 }
                    if let person = store.data.ownPerson, !person.standingOrders.isEmpty {
                        Text("Daueraufträge").font(.agoraSection).foregroundStyle(Palette.text).padding(.top, 6)
                        VStack(spacing: 0) {
                            ForEach(Array(person.standingOrders.enumerated()), id: \.offset) { index, order in
                                if index > 0 { Hairline() }
                                StandingOrderRow(order: order)
                            }
                        }
                        .card(padding: 0)
                    }
                } right: {
                    if let person = store.data.ownPerson {
                        Text("Verlauf").font(.agoraSection).foregroundStyle(Palette.text)
                        FinanceTimeline(person: person).card()
                    }
                }
            }
        }
        .sheet(item: $newRequest) { kind in NewRequestSheet(kind: kind) }
        .sheet(item: $openRequest) { request in RequestDetailSheet(request: request, canDecide: false) }
    }
}

struct StandingOrderRow: View {
    let order: StandingOrder

    var body: some View {
        HStack(spacing: 12) {
            IconTile(systemImage: "repeat", color: Palette.primary, size: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(order.note.isEmpty ? String(localized: "Dauerauftrag") : order.note).font(.system(size: 15, weight: .semibold)).foregroundStyle(Palette.text)
                Text(order.endDate.map { "seit \(Formats.shortDay(order.startDate)) – \(Formats.shortDay($0))" } ?? "seit \(Formats.shortDay(order.startDate))")
                    .font(.system(size: 13)).foregroundStyle(Palette.textSecondary)
            }
            Spacer()
            Text("\(Formats.money(order.amount)) / Monat").font(.system(size: 14.5, weight: .bold)).foregroundStyle(Palette.text)
        }
        .padding(14)
        .accessibilityElement(children: .combine)
    }
}

enum RequestKind: String, Identifiable, CaseIterable {
    case payment, status, expense
    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .payment: return "Zahlung"
        case .status: return "Status"
        case .expense: return "Ausgabe"
        }
    }
}

/// Member → treasurer request: payment (optionally as standing order), status change or expense with receipts.
struct NewRequestSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(ToastCenter.self) private var toasts
    @Environment(\.dismiss) private var dismiss
    @State var kind: RequestKind
    @State private var amount = ""
    @State private var date = Day.today()
    @State private var note = ""
    @State private var description = ""
    @State private var standingOrder = false
    @State private var newStatus = ""
    @State private var receipts: [PickedFile] = []
    @State private var busy = false
    @State private var error: String?

    init(kind: RequestKind) { _kind = State(initialValue: kind) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Art", selection: $kind) {
                        ForEach(RequestKind.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }
                Section {
                    if kind == .status {
                        Picker("Neuer Status", selection: $newStatus) {
                            ForEach(MemberStatus.allCases) { Text($0.label).tag($0.rawValue) }
                        }
                    } else {
                        AmountField(title: "Betrag", text: $amount)
                    }
                    DayPicker(title: kind == .payment && standingOrder ? "Startdatum" : "Datum", day: $date)
                    if kind == .payment {
                        TextField("Notiz", text: $note, axis: .vertical)
                        Toggle("Als Dauerauftrag einrichten", isOn: $standingOrder)
                    }
                    if kind == .expense {
                        TextField("Beschreibung", text: $description, axis: .vertical)
                    }
                } footer: {
                    if kind == .status {
                        Text("Der Kassenwart prüft die Statusänderung und übernimmt sie ab dem gewählten Datum.")
                    }
                }
                if kind == .expense {
                    Section("Belege") { ReceiptPicker(files: $receipts) }
                }
                if let error {
                    Section { Text(error).foregroundStyle(Palette.danger) }
                }
            }
            .navigationTitle("Neue Anfrage")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if busy { ProgressView() } else { Button("Senden", action: submit).bold() }
                }
            }
            .interactiveDismissDisabled(busy)
        }
        .onAppear {
            if newStatus.isEmpty { newStatus = store.data.ownPerson?.effectiveStatus.nilIfEmpty ?? MemberStatus.vollverdiener.rawValue }
        }
    }

    private func submit() {
        error = nil
        guard let user = store.user else { return }
        let value = Amount.parse(amount)
        if (kind != .status && amount.trimmingCharacters(in: .whitespaces).isEmpty) || date.isEmpty
            || (kind == .expense && description.trimmingCharacters(in: .whitespaces).isEmpty) {
            error = String(localized: "Bitte alle Felder ausfüllen.")
            return
        }
        if kind != .status, (value ?? 0) <= 0 {
            error = String(localized: "Ungültiger Betrag.")
            return
        }
        busy = true
        Task {
            defer { busy = false }
            do {
                let person = store.data.ownPerson
                var payload: [String: JSONValue] = [:]
                var type = kind.rawValue
                switch kind {
                case .status:
                    payload = ["newStatus": .string(newStatus), "date": .string(date)]
                case .payment:
                    if standingOrder { type = "standing_order" }
                    payload = ["amount": .string(String(format: "%.2f", value ?? 0)), "date": .string(date), "note": .string(note)]
                case .expense:
                    var names: [String] = []
                    for file in receipts {
                        names.append(try await store.repository.uploadReceipt(ownerName: person?.name ?? user.fullName, date: date,
                                                                              fileName: file.name, mimeType: file.mimeType, data: file.data))
                    }
                    let list = String(decoding: (try? JSONEncoder().encode(names)) ?? Data("[]".utf8), as: UTF8.self)
                    payload = ["amount": .string(String(format: "%.2f", value ?? 0)), "description": .string(description),
                               "date": .string(date), "receipt": .string(list)]
                }
                try await store.repository.submitRequest(user: user, person: person, type: type, data: payload)
                await store.refreshAll()
                toasts.show(String(localized: "Anfrage erfolgreich gesendet"))
                dismiss()
            } catch {
                self.error = APIError.text(error)
            }
        }
    }
}

extension String {
    var nilIfEmpty: String? { trimmingCharacters(in: .whitespaces).isEmpty ? nil : self }
}
