import SwiftUI

/// Common frame of the finance forms: navigation bar with cancel / confirm and an error line.
struct FormSheet<Content: View>: View {
    let title: LocalizedStringKey
    var confirm: LocalizedStringKey = "Speichern"
    var canConfirm = true
    var busy = false
    var error: String?
    let onConfirm: () -> Void
    @ViewBuilder var content: Content
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                content
                if let error {
                    Section { Text(error).foregroundStyle(Palette.danger) }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if busy { ProgressView() } else { Button(confirm, action: onConfirm).bold().disabled(!canConfirm) }
                }
            }
            .interactiveDismissDisabled(busy)
        }
    }
}

/// Runs a form action: busy state, error line, success toast and closing the sheet.
@MainActor
@Observable
final class FormAction {
    var busy = false
    var error: String?

    func run(toasts: ToastCenter, success: String, dismiss: DismissAction, _ work: @escaping () async throws -> Void) {
        guard !busy else { return }
        busy = true
        error = nil
        Task {
            defer { busy = false }
            do {
                try await work()
                toasts.show(success)
                dismiss()
            } catch {
                self.error = APIError.text(error)
            }
        }
    }
}

struct BookPaymentSheet: View {
    let person: Person
    let onDone: () -> Void
    @Environment(AppStore.self) private var store
    @Environment(ToastCenter.self) private var toasts
    @Environment(\.dismiss) private var dismiss
    @State private var action = FormAction()
    @State private var amount = ""
    @State private var date = Day.today()
    @State private var note = ""
    @State private var standingOrder = false

    var body: some View {
        let value = Amount.parse(amount) ?? 0
        FormSheet(title: "Zahlung buchen", confirm: "Buchen", canConfirm: value > 0 && !date.isEmpty, busy: action.busy, error: action.error, onConfirm: save) {
            Section {
                AmountField(title: "Betrag", text: $amount)
                DayPicker(title: standingOrder ? "Startdatum" : "Datum", day: $date)
                TextField("Notiz", text: $note, axis: .vertical)
                Toggle("Als Dauerauftrag einrichten", isOn: $standingOrder)
            } header: {
                Text(person.name)
            } footer: {
                if standingOrder { Text("Ab dem Startdatum wird der Betrag jeden Monat automatisch gebucht.") }
            }
        }
    }

    private func save() {
        let value = Amount.parse(amount) ?? 0
        action.run(toasts: toasts, success: String(localized: "Zahlung gebucht"), dismiss: dismiss) {
            try await store.repository.bookPayment(personId: person.id, amount: value, date: date, note: note, standingOrder: standingOrder)
            onDone()
        }
    }
}

struct ChangeStatusSheet: View {
    let person: Person
    let onDone: () -> Void
    @Environment(AppStore.self) private var store
    @Environment(ToastCenter.self) private var toasts
    @Environment(\.dismiss) private var dismiss
    @State private var action = FormAction()
    @State private var status = ""
    @State private var date = Day.today()

    var body: some View {
        FormSheet(title: "Status ändern", canConfirm: !status.isEmpty, busy: action.busy, error: action.error, onConfirm: save) {
            Section {
                // Opened from the fee list: plain status names like the list itself
                Picker("Neuer Status", selection: $status) {
                    ForEach(MemberStatus.allCases) { Text(MemberStatus.name($0.rawValue)).tag($0.rawValue) }
                }
                DayPicker(title: "Gültig ab", day: $date)
            } header: {
                Text(person.name)
            } footer: {
                Text("Ein Datum in der Vergangenheit ändert die Historie rückwirkend.")
            }
        }
        .onAppear { if status.isEmpty { status = person.effectiveStatus.nilIfEmpty ?? MemberStatus.vollverdiener.rawValue } }
    }

    private func save() {
        action.run(toasts: toasts, success: String(localized: "Status geändert"), dismiss: dismiss) {
            try await store.repository.changeStatus(personId: person.id, status: status, date: date)
            onDone()
        }
    }
}

struct ManageStandingOrderSheet: View {
    let person: Person
    let order: StandingOrder
    let onDone: () -> Void
    @Environment(AppStore.self) private var store
    @Environment(ToastCenter.self) private var toasts
    @Environment(\.dismiss) private var dismiss
    @State private var action = FormAction()
    @State private var endDate = ""
    @State private var confirmDelete = false

    var body: some View {
        let past = !endDate.isEmpty && endDate < Day.today()
        FormSheet(title: "Dauerauftrag verwalten", confirm: "Speichern", canConfirm: !endDate.isEmpty, busy: action.busy, error: action.error, onConfirm: end) {
            Section {
                LabeledContent("Betrag", value: "\(Formats.money(order.amount)) / Monat")
                LabeledContent("Seit", value: Formats.shortDay(order.startDate))
                if !order.note.isEmpty { LabeledContent("Notiz", value: order.note) }
            } header: {
                Text(person.name)
            }
            Section {
                DayPicker(title: "Enddatum", day: $endDate)
            } footer: {
                if past {
                    Text("Das Datum liegt in der Vergangenheit: Danach automatisch gebuchte Zahlungen werden wieder entfernt und der Dauerauftrag endet.")
                        .foregroundStyle(Palette.warning)
                } else {
                    Text("Zahlungen werden nur bis zu diesem Datum erstellt.")
                }
            }
            Section {
                Button("Eintrag ganz löschen", role: .destructive) { confirmDelete = true }
            }
        }
        .onAppear { if endDate.isEmpty { endDate = order.endDate ?? Day.today() } }
        .confirmationDialog("Dauerauftrag wirklich komplett entfernen? Bereits gebuchte Zahlungen bleiben erhalten.",
                            isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Löschen", role: .destructive, action: delete)
        }
    }

    private func end() {
        action.run(toasts: toasts, success: String(localized: "Dauerauftrag aktualisiert"), dismiss: dismiss) {
            try await store.repository.endStandingOrder(personId: person.id, orderId: order.id, endDate: endDate)
            onDone()
        }
    }

    private func delete() {
        action.run(toasts: toasts, success: String(localized: "Dauerauftrag gelöscht"), dismiss: dismiss) {
            try await store.repository.deleteStandingOrder(personId: person.id, orderId: order.id)
            onDone()
        }
    }
}

/// Donation or expense booked by the treasurer.
struct FinanceEntrySheet: View {
    enum Kind: String, Identifiable { case donation, expense; var id: String { rawValue } }

    let kind: Kind
    let onDone: () -> Void
    @Environment(AppStore.self) private var store
    @Environment(ToastCenter.self) private var toasts
    @Environment(\.dismiss) private var dismiss
    @State private var action = FormAction()
    @State private var amount = ""
    @State private var name = ""
    @State private var date = Day.today()
    @State private var description = ""
    @State private var receipts: [PickedFile] = []

    var body: some View {
        let value = Amount.parse(amount) ?? 0
        let valid = value > 0 && !name.trimmingCharacters(in: .whitespaces).isEmpty && !date.isEmpty
            && (kind == .donation || !description.trimmingCharacters(in: .whitespaces).isEmpty)
        FormSheet(title: kind == .donation ? "Spende erfassen" : "Ausgabe buchen", canConfirm: valid, busy: action.busy, error: action.error, onConfirm: save) {
            Section {
                AmountField(title: "Betrag", text: $amount)
                TextField(kind == .donation ? "Spender" : "Ausgelegt von", text: $name)
                    .textContentType(.name)
                DayPicker(title: "Datum", day: $date)
                TextField("Beschreibung", text: $description, axis: .vertical)
            }
            if kind == .expense {
                Section("Belege") { ReceiptPicker(files: $receipts) }
            }
        }
    }

    private func save() {
        let value = Amount.parse(amount) ?? 0
        let files = receipts
        action.run(toasts: toasts, success: kind == .donation ? String(localized: "Spende gespeichert") : String(localized: "Ausgabe gespeichert"), dismiss: dismiss) {
            if kind == .donation {
                try await store.repository.addDonation(amount: value, name: name, date: date, description: description)
            } else {
                var names: [String] = []
                for file in files {
                    names.append(try await store.repository.uploadReceipt(ownerName: name, date: date, fileName: file.name, mimeType: file.mimeType, data: file.data))
                }
                try await store.repository.addExpense(amount: value, issuer: name, date: date, description: description, receipts: names)
            }
            onDone()
        }
    }
}
