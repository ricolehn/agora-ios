import SwiftUI
import PhotosUI

/// Create or edit an event / appointment (native form).
struct EventEditView: View {
    let eventId: String?
    let initialType: String
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router
    @Environment(ToastCenter.self) private var toasts
    @State private var input = EventInput()
    @State private var multiDay = false
    @State private var hasTimes = true
    @State private var prepared = false
    @State private var busy = false
    @State private var error: String?
    @State private var photo: PhotosPickerItem?
    @State private var uploading = false

    private var isManager: Bool { store.user.map { $0.managesEvents || $0.isAdmin } ?? false }
    private var existing: AgoraEvent? { eventId.flatMap { store.data.event($0) } }

    var body: some View {
        Form {
            if isManager {
                Section {
                    Picker("Art", selection: $input.eventType.animation()) {
                        Text("Termin").tag("termin")
                        Text("Event").tag("event")
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                } footer: {
                    Text(input.eventType == "termin"
                         ? "Regulärer Termin (z. B. Bistro, Gebetstreff, Probe) – erscheint im Terminkalender."
                         : "Besonderes Event (z. B. Jugendtreff, Konzert, Fest) – mit Titelbild & Programm.")
                }
            }
            Section {
                TextField("Titel", text: $input.title)
                    .font(.system(size: 17, weight: .semibold))
                DayPicker(title: multiDay ? "Startdatum" : "Datum", day: $input.date)
                Toggle("Mehrtägig", isOn: $multiDay.animation())
                if multiDay {
                    DayPicker(title: "Enddatum", day: $input.endDate)
                } else {
                    Toggle("Mit Uhrzeit", isOn: $hasTimes.animation())
                    if hasTimes {
                        ClockPicker(title: "Beginn", time: $input.startTime)
                        ClockPicker(title: "Ende", time: $input.endTime)
                    }
                }
                TextField("Ort", text: $input.location)
            }
            Section {
                TextField("Beschreibung (Markdown möglich)", text: $input.description, axis: .vertical)
                    .lineLimit(4...14)
            } header: {
                Text("Beschreibung")
            }
            Section {
                coverPicker
            } header: {
                Text("Titelbild (16:9)")
            }
            Section {
                if isManager && input.eventType == "event" {
                    Toggle(isOn: $input.isPinned) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Großevent / Highlight")
                            Text("Wird für alle ganz oben angezeigt").font(.caption).foregroundStyle(Palette.textSecondary)
                        }
                    }
                }
                Toggle("Anmeldung erforderlich", isOn: $input.requiresRegistration.animation())
                if input.requiresRegistration {
                    Stepper("Min. Teilnehmende: \(input.minParticipants)", value: $input.minParticipants, in: 0...500)
                    Stepper(value: $input.maxParticipants, in: 0...1000) {
                        if input.maxParticipants == 0 {
                            Text("Max. Teilnehmende: unbegrenzt")
                        } else {
                            Text("Max. Teilnehmende: \(input.maxParticipants)")
                        }
                    }
                }
            }
            if !store.data.groups.isEmpty {
                Section {
                    ForEach(store.data.groups) { group in
                        // The web editor saves group names, the apps ids; both count as chosen
                        let selected = input.targetGroups.contains(group.id) || input.targetGroups.contains(group.name)
                        Button {
                            if selected {
                                input.targetGroups.removeAll { $0 == group.id || $0 == group.name }
                            } else {
                                input.targetGroups.append(group.id)
                            }
                        } label: {
                            HStack {
                                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(selected ? Palette.primary : Palette.textSecondary)
                                Text(group.name).foregroundStyle(Palette.text)
                                Spacer()
                            }
                        }
                    }
                } header: {
                    Text("Zielgruppen")
                } footer: {
                    Text("Nur die gewählten Gruppen sehen den Eintrag. Ohne Auswahl sehen ihn alle Mitglieder.")
                }
            }
            if eventId == nil && isManager && input.eventType == "termin" {
                Section {
                    Toggle("Wiederholen", isOn: $input.isRecurring.animation())
                    if input.isRecurring {
                        Picker("Rhythmus", selection: $input.recurringRule) {
                            Text("Wöchentlich").tag("weekly")
                            Text("Alle zwei Wochen").tag("biweekly")
                            Text("Monatlich").tag("monthly")
                        }
                        Stepper("Anzahl: \(input.recurringCount)", value: $input.recurringCount, in: 2...52)
                    }
                }
            }
            if let error {
                Section { Text(error).foregroundStyle(Palette.danger) }
            }
        }
        .navigationTitle(eventId != nil ? (input.eventType == "termin" ? "Termin bearbeiten" : "Event bearbeiten")
                         : (input.eventType == "termin" ? "Neuer Termin" : "Neues Event"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                if busy { ProgressView() } else { Button(eventId == nil ? "Veröffentlichen" : "Speichern", action: save).bold().disabled(uploading) }
            }
        }
        .onAppear(perform: prepare)
        .onChange(of: photo) { _, item in upload(item) }
    }

    @ViewBuilder
    private var coverPicker: some View {
        if let url = store.api.absolute(input.imageUrl) {
            CoverImage(url: url) { Palette.surfaceAlt }
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        HStack {
            PhotosPicker(selection: $photo, matching: .images) {
                if uploading {
                    ProgressView()
                } else {
                    Label(input.imageUrl.isEmpty ? "Bild auswählen" : "Bild ändern", systemImage: "photo")
                }
            }
            .disabled(uploading)
            if !input.imageUrl.isEmpty {
                Spacer()
                Button("Entfernen", role: .destructive) { input.imageUrl = "" }
                    .buttonStyle(.borderless)
            }
        }
    }

    private func prepare() {
        guard !prepared else { return }
        prepared = true
        if let event = existing {
            input = EventInput(title: event.title, date: event.date, endDate: event.endDate, startTime: event.startTime, endTime: event.endTime,
                               location: event.location, description: event.description, eventType: event.eventType, isPinned: event.isPinned,
                               requiresRegistration: event.requiresRegistration, minParticipants: event.minParticipants,
                               maxParticipants: event.maxParticipants, targetGroups: event.targetGroups, imageUrl: event.imageUrl)
            multiDay = event.isMultiDay
            hasTimes = !event.startTime.isEmpty
        } else {
            input.eventType = isManager ? initialType : "event"
            input.date = Day.today()
            input.startTime = "10:00"
            input.endTime = "12:00"
            input.duties = store.data.eventSettings.defaultDuties
        }
        if input.endDate.isEmpty { input.endDate = Day.adding(1, to: input.date) ?? input.date }
    }

    private func upload(_ item: PhotosPickerItem?) {
        guard let item else { return }
        uploading = true
        Task {
            defer {
                uploading = false
                photo = nil
            }
            do {
                guard let data = try await item.loadTransferable(type: Data.self),
                      let jpeg = ImageTools.jpeg(from: data, aspect: 16 / 9, maxWidth: 1600) else {
                    throw APIError(status: 0, message: String(localized: "Hochladen fehlgeschlagen."))
                }
                input.imageUrl = try await store.repository.uploadEventImage(jpeg: jpeg)
            } catch {
                toasts.show(String(localized: "Hochladen fehlgeschlagen."), error: true)
            }
        }
    }

    private func save() {
        error = nil
        guard !input.title.trimmingCharacters(in: .whitespaces).isEmpty else {
            error = String(localized: "Titel ist erforderlich")
            return
        }
        var final = input
        if multiDay {
            final.startTime = ""
            final.endTime = ""
            if final.endDate < final.date { final.endDate = final.date }
        } else {
            final.endDate = ""
            if !hasTimes {
                final.startTime = ""
                final.endTime = ""
            }
        }
        if !(isManager && final.eventType == "event") { final.isPinned = false }
        if !isManager && eventId == nil { final.eventType = "event" }
        if !final.requiresRegistration {
            final.minParticipants = 0
            final.maxParticipants = 0
        }
        if eventId != nil || final.eventType != "termin" { final.isRecurring = false }
        busy = true
        Task {
            defer { busy = false }
            do {
                try await store.repository.saveEvent(id: eventId, final)
                await store.refreshAll()
                toasts.show(String(localized: "Gespeichert"))
                router.back()
            } catch {
                self.error = APIError.text(error)
            }
        }
    }
}
