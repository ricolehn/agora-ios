import SwiftUI

/// A person or group chosen for a new entry; asked when the entry is saved.
struct PlanPick: Identifiable, Hashable {
    var userId: String?
    var groupId: String?
    var label: String
    var id: String { "\(userId ?? "")|\(groupId ?? "")" }
}

/// One entry of the plan (web: #plan-entry-modal). New: a task or a song, people to ask (several),
/// "Im Ablauf" with position, duration, key and note. Existing: people are asked / removed right away,
/// the rest is saved with "Speichern". Like PlanEntrySheet.kt of the Android app.
struct PlanEntrySheet: View {
    let event: AgoraEvent
    @Binding var items: [ProgramItem]
    let target: PlanEntryTarget
    @Environment(AppStore.self) private var store
    @Environment(ToastCenter.self) private var toasts
    @Environment(\.dismiss) private var dismiss

    @State private var prepared = false
    @State private var songs: [PlanSong]?
    @State private var itemId: String?
    @State private var role: String?
    @State private var kind = "task"
    @State private var name = ""
    @State private var songId = ""
    @State private var songQuery = ""
    @State private var inProgram = false
    @State private var position = 0
    @State private var minutes = ""
    @State private var key = ""
    @State private var note = ""
    @State private var picks: [PlanPick] = []
    @State private var picking = false
    @State private var confirmDelete = false
    @State private var removing: Duty?
    @State private var busy = false
    @State private var error: String?

    private var editing: Bool { !target.isNew }
    private var songList: [PlanSong] { songs ?? [] }
    private var item: ProgramItem? { itemId.flatMap { id in items.first { $0.id == id } } }
    private var others: [ProgramItem] { items.filter { $0.id != item?.id } }
    private var entryName: String { editing ? (role ?? item.map { Plan.itemTitle($0, songList) } ?? "") : "" }
    private var people: [Duty] {
        guard editing, let role else { return [] }
        return event.duties.filter { Plan.sameName($0.roleName, role) && $0.hasAssignee }
    }
    private var isSongEntry: Bool { kind == "song" || !(item?.songId.isEmpty ?? true) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text([event.title, Formats.eventWhen(event)].filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(.system(size: 13.5)).foregroundStyle(Palette.textSecondary)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 0, leading: 4, bottom: 0, trailing: 4))
                }
                if !editing { whatSection }
                whoSection
                programSection
                if let error {
                    Section { Text(error).foregroundStyle(Palette.danger) }
                }
                if editing {
                    Section {
                        Button("Eintrag löschen", role: .destructive) { confirmDelete = true }
                    }
                }
            }
            .navigationTitle(editing ? (entryName.isEmpty ? String(localized: "Eintrag bearbeiten") : entryName) : String(localized: "Neuer Eintrag"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if busy { ProgressView() } else { Button("Speichern", action: save).bold() }
                }
            }
            .interactiveDismissDisabled(busy)
            .disabled(busy)
            .sheet(isPresented: $picking) {
                PlanPickerSheet(title: pickerTitle) { pick in
                    if editing {
                        askNow(pick)
                    } else if !picks.contains(where: { (pick.userId != nil && $0.userId == pick.userId) || (pick.groupId != nil && $0.groupId == pick.groupId) }) {
                        picks.append(pick)
                    }
                }
            }
            .confirmationDialog("„\(entryName)“ mit allen Anfragen dafür löschen?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Löschen", role: .destructive, action: deleteEntry)
            }
            .confirmationDialog("Diesen Eintrag wirklich entfernen?", isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }),
                                titleVisibility: .visible) {
                Button("Entfernen", role: .destructive) { if let duty = removing { remove(duty) } }
            }
        }
        .task {
            if songs == nil { songs = (try? await store.repository.planSongs()) ?? [] }
        }
        .onAppear(perform: prepare)
    }

    // MARK: Sections

    @ViewBuilder
    private var whatSection: some View {
        Section {
            Picker("Art", selection: $kind) {
                Text("Aufgabe / Punkt").tag("task")
                Text("Lied").tag("song")
            }
            .pickerStyle(.segmented)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())
            if kind == "task" {
                TextField("Name, z. B. Predigt, Technik, Begrüßung", text: $name)
            } else {
                songPicker
            }
        }
    }

    @ViewBuilder
    private var songPicker: some View {
        let chosen = songList.first { $0.id == songId }
        if let chosen {
            HStack(spacing: 8) {
                Image(systemName: "music.note").foregroundStyle(Palette.primary)
                Text(chosen.title).font(.system(size: 15, weight: .semibold)).foregroundStyle(Palette.text)
                Spacer()
                if !chosen.key.isEmpty { PlanKeyChip(key: chosen.key) }
            }
            .listRowBackground(Palette.primary.opacity(0.08))
        }
        TextField("Im Liederbuch suchen…", text: $songQuery)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
        if songs == nil {
            ProgressView().frame(maxWidth: .infinity)
        } else if chosen == nil || !songQuery.trimmingCharacters(in: .whitespaces).isEmpty {
            let needle = songQuery.trimmingCharacters(in: .whitespaces).lowercased()
            let found = songList.filter { needle.isEmpty || $0.title.lowercased().contains(needle) || $0.artist.lowercased().contains(needle) }.prefix(30)
            if found.isEmpty {
                Text("Kein Lied gefunden").foregroundStyle(Palette.textSecondary)
            }
            ForEach(Array(found)) { song in
                Button {
                    songId = song.id
                    if key.trimmingCharacters(in: .whitespaces).isEmpty { key = song.key }
                    songQuery = ""
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(song.title).font(.system(size: 15, weight: .semibold)).foregroundStyle(Palette.text)
                        let meta = [song.artist, song.key].filter { !$0.isEmpty }.joined(separator: " · ")
                        if !meta.isEmpty { Text(meta).font(.system(size: 12.5)).foregroundStyle(Palette.textSecondary) }
                    }
                }
            }
        }
    }

    /// Who? New entries collect the people (asked on save), existing ones ask / remove right away.
    @ViewBuilder
    private var whoSection: some View {
        Section("Wer?") {
            if editing {
                if people.isEmpty { PlanOpenLabel(long: true) }
                ForEach(people) { duty in
                    HStack {
                        PlanName(duty: duty, short: false)
                        Spacer()
                        Button { removing = duty } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Palette.textSecondary) }
                            .buttonStyle(.borderless)
                            .accessibilityLabel("Entfernen")
                    }
                }
            } else {
                ForEach(picks) { pick in
                    HStack(spacing: 8) {
                        if pick.groupId != nil {
                            Image(systemName: "person.3.fill").font(.system(size: 11)).foregroundStyle(Palette.indigo)
                                .frame(width: 24, height: 24)
                                .background(Palette.indigo.opacity(0.14), in: Circle())
                        } else {
                            Avatar(userId: pick.userId, name: pick.label, size: 24)
                        }
                        Text(pick.label)
                        Spacer()
                        Button { picks.removeAll { $0.id == pick.id } } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Palette.textSecondary) }
                            .buttonStyle(.borderless)
                            .accessibilityLabel("Entfernen")
                    }
                }
            }
            let asked = editing ? !people.isEmpty : !picks.isEmpty
            Button { picking = true } label: {
                Label(asked ? "Weitere Person anfragen" : "Person oder Gruppe anfragen", systemImage: "person.badge.plus")
            }
        }
    }

    @ViewBuilder
    private var programSection: some View {
        Section {
            Toggle("Im Ablauf", isOn: $inProgram)
            if inProgram {
                Picker("Position", selection: $position) {
                    Text("Am Anfang").tag(0)
                    ForEach(Array(others.enumerated()), id: \.offset) { index, other in
                        Text("Nach „\(Plan.itemTitle(other, songList))“").tag(index + 1)
                    }
                }
                TextField("Dauer (Min.)", text: $minutes)
                    .keyboardType(.numberPad)
                    .onChange(of: minutes) { _, value in
                        let digits = String(value.filter(\.isNumber).prefix(3))
                        if digits != value { minutes = digits }
                    }
                if isSongEntry {
                    TextField("Tonart", text: $key)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .onChange(of: key) { _, value in if value.count > 4 { key = String(value.prefix(4)) } }
                }
                TextField("Notiz (optional)", text: $note, axis: .vertical)
                    .onChange(of: note) { _, value in if value.count > 300 { note = String(value.prefix(300)) } }
            }
        } footer: {
            if inProgram && Plan.isTime(event.startTime) {
                let place = min(max(position, 0), others.count)
                let time = Plan.addMinutes(event.startTime, Plan.total(Array(others.prefix(place))))
                let duration = Int(minutes) ?? 0
                Text(duration > 0 ? "Beginnt um \(time) Uhr, bis \(Plan.addMinutes(time, duration)) Uhr" : "Ohne Dauer legt der Eintrag nur die Reihenfolge fest.")
            }
        }
    }

    private var pickerTitle: String {
        if !entryName.isEmpty { return entryName }
        if kind == "song" { return songList.first { $0.id == songId }?.title ?? "" }
        return name.trimmingCharacters(in: .whitespaces)
    }

    // MARK: Actions

    private func prepare() {
        guard !prepared else { return }
        prepared = true
        let found = target.itemId.flatMap { id in items.first { $0.id == id } }
            ?? target.role.flatMap { role in items.first { Plan.itemTask($0, [role], []) != nil } }
        itemId = found?.id
        // The task of an existing entry: its own, else the one the item points to
        role = target.role ?? found.flatMap { Plan.itemTask($0, Plan.roleNames(event), []) }
        kind = found.map { $0.songId.isEmpty ? "task" : "song" } ?? "task"
        name = found?.title ?? target.role ?? ""
        songId = found?.songId ?? ""
        inProgram = found != nil
        position = found.flatMap { item in items.firstIndex { $0.id == item.id } } ?? items.filter { $0.id != found?.id }.count
        minutes = found?.minutes.map { String($0) } ?? ""
        key = found?.songKey ?? ""
        note = found?.note ?? ""
    }

    /// Runs one action with the busy state; errors stay in the form.
    private func run(success: String?, _ work: @escaping () async throws -> Void, done: (() -> Void)? = nil) {
        guard !busy else { return }
        busy = true
        error = nil
        Task {
            defer { busy = false }
            do {
                try await work()
                if let success { toasts.show(success) }
                done?()
            } catch is CancellationError {
            } catch {
                self.error = APIError.text(error)
            }
        }
    }

    /// Existing entry without a task yet: the item's title becomes its task (and the item points to it).
    private func ensureRole() async throws -> String? {
        if let role { return role }
        guard let current = item else { return nil }
        let newRole = Plan.itemTitle(current, songList).trimmingCharacters(in: .whitespaces)
        if !Plan.sameName(current.who, newRole) {
            let updated = items.map { other -> ProgramItem in
                var copy = other
                if copy.id == current.id { copy.who = newRole }
                return copy
            }
            items = try await store.repository.saveProgram(eventId: event.id, items: updated).items
        }
        role = newRole
        return newRole
    }

    private func askNow(_ pick: PlanPick) {
        run(success: pick.groupId != nil ? String(localized: "Gruppe erfolgreich eingeteilt!") : String(localized: "Dienstanfrage versendet!")) {
            guard let role = try await ensureRole() else { return }
            if let slot = event.duties.first(where: { Plan.sameName($0.roleName, role) && $0.status == "open" }) {
                try await store.repository.assignDuty(id: slot.id, userId: pick.userId, groupId: pick.groupId)
            } else {
                try await store.repository.addDuty(eventId: event.id, roleName: role, userId: pick.userId, groupId: pick.groupId)
            }
            await store.refreshEvents()
        }
    }

    private func save() {
        let song = kind == "song" ? songList.first(where: { $0.id == songId }) : nil
        if kind == "song" && song == nil && !editing {
            error = String(localized: "Bitte wähle ein Lied aus.")
            return
        }
        let entry = editing ? (role ?? item.map { Plan.itemTitle($0, songList) } ?? "") : (song?.title ?? name.trimmingCharacters(in: .whitespaces))
        if entry.trimmingCharacters(in: .whitespaces).isEmpty {
            error = String(localized: "Bitte gib einen Namen ein.")
            return
        }
        let duration = Int(minutes.trimmingCharacters(in: .whitespaces)).map { min(max($0, 0), 600) }
        let songKey = song != nil || !(item?.songId.isEmpty ?? true) ? key.trimmingCharacters(in: .whitespaces) : ""
        let noteText = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let chosen = picks
        let current = item
        let place = position
        let keepInProgram = inProgram
        let isEditing = editing
        let existingRole = role
        run(success: chosen.isEmpty ? String(localized: "Gespeichert") : String(localized: "Dienstanfrage versendet!")) {
            let roles = Plan.roleNames(event)
            let roleName = existingRole ?? roles.first(where: { Plan.sameName($0, entry) }) ?? entry
            let hasTask = roles.contains { Plan.sameName($0, roleName) }
            // People are asked through the duty roster (requests, reminders, apps)
            if !chosen.isEmpty {
                for pick in chosen {
                    try await store.repository.addDuty(eventId: event.id, roleName: roleName, userId: pick.userId, groupId: pick.groupId)
                }
            } else if !hasTask && (!keepInProgram || isEditing) {
                // A task without a moment always stays on the roster (also when it leaves the order)
                try await store.repository.addEmptyTask(eventId: event.id, roleName: roleName)
            }
            var next = items
            let linked = current ?? next.first(where: { Plan.itemTask($0, [roleName], songList) != nil })
            if keepInProgram {
                let updated: ProgramItem
                if var existing = linked {
                    existing.minutes = duration
                    existing.note = noteText
                    existing.songKey = songKey
                    updated = existing
                } else {
                    updated = ProgramItem(title: song != nil ? "" : entry,
                                          minutes: duration,
                                          who: !chosen.isEmpty || hasTask || isEditing ? roleName : "",
                                          note: noteText,
                                          songId: song?.id ?? "",
                                          songKey: songKey)
                }
                if let linked { next.removeAll { $0.id == linked.id } }
                next.insert(updated, at: min(max(place, 0), next.count))
            } else if let linked {
                next.removeAll { $0.id == linked.id }
            }
            if next != items {
                items = try await store.repository.saveProgram(eventId: event.id, items: next).items
            }
            await store.refreshEvents()
        } done: {
            dismiss()
        }
    }

    private func deleteEntry() {
        let role = self.role
        let current = item
        run(success: String(localized: "Eintrag gelöscht")) {
            for duty in event.duties where role != nil && Plan.sameName(duty.roleName, role) {
                try await store.repository.deleteDuty(id: duty.id)
            }
            let next = items.filter { other in
                other.id != current?.id && !(role != nil && Plan.itemTask(other, [role ?? ""], songList) != nil)
            }
            if next.count != items.count {
                items = try await store.repository.saveProgram(eventId: event.id, items: next).items
            }
            await store.refreshEvents()
        } done: {
            dismiss()
        }
    }

    private func remove(_ duty: Duty) {
        let last = event.duties.filter { Plan.sameName($0.roleName, duty.roleName) }.count == 1
        run(success: String(localized: "Entfernt")) {
            try await store.repository.deleteDuty(id: duty.id)
            // The task stays (empty) when its last person goes
            if last { try await store.repository.addEmptyTask(eventId: event.id, roleName: duty.roleName) }
            await store.refreshEvents()
        }
    }
}

/// "Person oder Gruppe anfragen": search members (asked) or groups (assigned).
struct PlanPickerSheet: View {
    let title: String
    let onPick: (PlanPick) -> Void
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var candidates: Candidates?
    @State private var kind = 0
    @State private var query = ""

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Art", selection: $kind) {
                        Text("Person").tag(0)
                        Text("Gruppe").tag(1)
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }
                if let candidates {
                    let needle = query.trimmingCharacters(in: .whitespaces)
                    if kind == 0 {
                        ForEach(candidates.candidates.filter { needle.isEmpty || $0.name.localizedCaseInsensitiveContains(needle) || $0.email.localizedCaseInsensitiveContains(needle) }) { person in
                            HStack {
                                Avatar(userId: person.id, name: person.name, size: 34)
                                VStack(alignment: .leading) {
                                    Text(person.name.isEmpty ? person.email : person.name)
                                    if !person.email.isEmpty { Text(person.email).font(.caption).foregroundStyle(Palette.textSecondary) }
                                }
                                Spacer()
                                Button("Anfragen") { pick(PlanPick(userId: person.id, label: person.name.isEmpty ? person.email : person.name)) }
                                    .buttonStyle(.borderless).bold()
                            }
                        }
                    } else {
                        ForEach(candidates.groups.filter { needle.isEmpty || $0.name.localizedCaseInsensitiveContains(needle) }) { group in
                            HStack {
                                IconTile(systemImage: "person.3.fill", color: Palette.indigo, size: 34)
                                VStack(alignment: .leading) {
                                    Text(group.name)
                                    Text("Gruppe fest einteilen").font(.caption).foregroundStyle(Palette.textSecondary)
                                }
                                Spacer()
                                Button("Zuweisen") { pick(PlanPick(groupId: group.id, label: group.name)) }
                                    .buttonStyle(.borderless).bold()
                            }
                        }
                    }
                } else {
                    ProgressView().frame(maxWidth: .infinity)
                }
            }
            .searchable(text: $query, prompt: Text(kind == 0 ? "Person suchen…" : "Gruppe suchen…"))
            .navigationTitle("Person oder Gruppe anfragen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } } }
            .safeAreaInset(edge: .top) {
                if !title.isEmpty {
                    Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(Palette.textSecondary)
                        .frame(maxWidth: .infinity).padding(.vertical, 6).background(.bar)
                }
            }
        }
        .task { candidates = (try? await store.repository.candidates()) ?? Candidates() }
    }

    private func pick(_ choice: PlanPick) {
        dismiss()
        onPick(choice)
    }
}
