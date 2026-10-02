import SwiftUI

// MARK: - Registration

/// "Anmeldung": seats, own state, attendees (`.event-reg-card`).
struct RegistrationCard: View {
    let event: AgoraEvent
    @Environment(AppStore.self) private var store
    @Environment(ToastCenter.self) private var toasts
    @State private var runner = ActionRunner()
    @State private var attendees: Attendees?
    @State private var showList = false
    @State private var removing: Attendee?

    var body: some View {
        let max = event.maxParticipants
        let past = event.isPast()
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                IconTile(systemImage: "person.2.fill", color: Palette.primary, size: 38)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Anmeldung").font(.system(size: 16, weight: .heavy)).foregroundStyle(Palette.text)
                    Text(meta).font(.system(size: 13)).foregroundStyle(Palette.textSecondary)
                }
            }
            if max > 0 {
                CapsuleProgress(value: Double(event.registeredCount) / Double(max),
                                fill: event.isFull ? LinearGradient(colors: [Palette.warning, Palette.danger], startPoint: .leading, endPoint: .trailing) : Palette.button)
            }
            stateBand(past: past)
            attendeeSection
        }
        .card()
        .task(id: "\(event.id)-\(event.registeredCount)-\(event.waitlistCount)") { await loadAttendees() }
        .confirmationDialog(removing.map { "\($0.name) von der Teilnehmerliste entfernen?" } ?? "",
                            isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }), titleVisibility: .visible) {
            Button("Entfernen", role: .destructive) {
                if let attendee = removing { remove(attendee) }
            }
        }
    }

    private var meta: String {
        var parts: [String] = []
        if event.maxParticipants > 0 {
            parts.append(String(localized: "\(event.registeredCount) von \(event.maxParticipants) Plätzen belegt"))
            let free = event.maxParticipants - event.registeredCount
            parts.append(free > 0 ? String(localized: "\(free) frei") : String(localized: "ausgebucht"))
        } else {
            parts.append(String(localized: "\(event.registeredCount) angemeldet"))
        }
        if event.minParticipants > 0 { parts.append(String(localized: "mind. \(event.minParticipants)")) }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder
    private func stateBand(past: Bool) -> some View {
        if past {
            band(color: Palette.slate, icon: "clock",
                 title: event.isRegistered ? "Du warst angemeldet" : "Die Anmeldung ist beendet",
                 subtitle: "Das Event ist vorbei.", action: nil)
        } else if event.isRegistered {
            band(color: Palette.success, icon: "checkmark", title: "Du bist angemeldet", subtitle: "Wir freuen uns auf dich!",
                 action: ("Abmelden", { register(false) }))
        } else if event.isWaitlisted {
            band(color: Palette.warning, icon: "hourglass", title: "Du stehst auf der Warteliste",
                 subtitle: "Du rückst nach, sobald ein Platz frei wird.", action: ("Verlassen", { register(false) }))
        } else if event.isFull {
            Button { register(true) } label: { BusyLabel(title: "Auf Warteliste setzen", systemImage: "clock", busy: runner.busy) }
                .buttonStyle(.agoraSecondary)
                .disabled(runner.busy)
        } else {
            Button { register(true) } label: { BusyLabel(title: "Verbindlich anmelden", systemImage: "checkmark", busy: runner.busy) }
                .buttonStyle(.agoraPrimary)
                .disabled(runner.busy)
        }
    }

    private func band(color: Color, icon: String, title: LocalizedStringKey, subtitle: LocalizedStringKey,
                      action: (LocalizedStringKey, () -> Void)?) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(color, in: Circle())
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 15, weight: .bold)).foregroundStyle(Palette.text)
                Text(subtitle).font(.system(size: 13)).foregroundStyle(Palette.textSecondary)
            }
            Spacer(minLength: 0)
            if let action {
                Button(action.0, action: action.1)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Palette.textSecondary)
                    .disabled(runner.busy)
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: Radius.nested, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.nested, style: .continuous).strokeBorder(color.opacity(0.3), lineWidth: 1))
    }

    @ViewBuilder
    private var attendeeSection: some View {
        let registered = attendees?.registered ?? []
        let waitlist = attendees?.waitlist ?? []
        Hairline()
        Button {
            withAnimation(.snappy) { showList.toggle() }
        } label: {
            HStack(spacing: 10) {
                if registered.isEmpty {
                    Text("Noch niemand angemeldet").font(.system(size: 14.5, weight: .semibold)).foregroundStyle(Palette.textSecondary)
                } else {
                    AvatarStack(people: registered)
                    Text("Teilnehmer").font(.system(size: 15, weight: .bold)).foregroundStyle(Palette.text)
                    CountBadge(count: registered.count, color: Palette.slate)
                }
                Spacer()
                Image(systemName: "chevron.down")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Palette.textSecondary)
                    .rotationEffect(.degrees(showList ? 180 : 0))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        if showList {
            VStack(alignment: .leading, spacing: 8) {
                if attendees == nil {
                    ProgressView().frame(maxWidth: .infinity)
                } else if registered.isEmpty && waitlist.isEmpty {
                    Text("Sobald sich jemand anmeldet, erscheint die Person hier.").font(.system(size: 14)).foregroundStyle(Palette.textSecondary)
                } else {
                    ForEach(registered) { attendeeRow($0, waiting: false) }
                    if !waitlist.isEmpty {
                        CapsLabel("Warteliste · \(waitlist.count)", color: Palette.amberText).padding(.top, 6)
                        ForEach(waitlist) { attendeeRow($0, waiting: true) }
                    }
                }
            }
            .transition(.opacity)
        }
    }

    private func attendeeRow(_ attendee: Attendee, waiting: Bool) -> some View {
        HStack(spacing: 10) {
            Avatar(userId: attendee.userId, name: attendee.name, size: 32)
            Text(attendee.name).font(.system(size: 15, weight: .semibold)).foregroundStyle(waiting ? Palette.amberText : Palette.text)
            Spacer()
            if event.canEdit {
                Button { removing = attendee } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Palette.textSecondary) }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(attendee.name) entfernen")
            }
        }
    }

    private func loadAttendees() async {
        if let loaded = try? await store.repository.attendees(eventId: event.id) { attendees = loaded }
    }

    private func register(_ join: Bool) {
        let waitlist = event.isFull
        runner.run(toasts, success: join ? (waitlist ? String(localized: "Auf die Warteliste gesetzt") : String(localized: "Erfolgreich verbindlich angemeldet!"))
                   : String(localized: "Erfolgreich abgemeldet")) {
            try await store.repository.register(eventId: event.id, join)
            await store.refreshAll()
        }
    }

    private func remove(_ attendee: Attendee) {
        runner.run(toasts, success: String(localized: "Entfernt")) {
            try await store.repository.removeAttendee(eventId: event.id, userId: attendee.userId)
            await store.refreshEvents()
            await loadAttendees()
        }
    }
}

/// Up to five overlapping avatars and "+N".
struct AvatarStack: View {
    let people: [Attendee]

    var body: some View {
        HStack(spacing: -8) {
            ForEach(people.prefix(5)) { person in
                Avatar(userId: person.userId, name: person.name, size: 28)
                    .overlay(Circle().strokeBorder(Palette.surface, lineWidth: 2))
            }
            if people.count > 5 {
                Text("+\(people.count - 5)")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Palette.textSecondary)
                    .frame(height: 28)
                    .padding(.horizontal, 8)
                    .background(Palette.surfaceAlt, in: Capsule())
                    .overlay(Capsule().strokeBorder(Palette.surface, lineWidth: 2))
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Duty roster

/// "Dienstplan": tasks grouped by role with people, requests, groups and open slots (`.event-duty-card`).
struct DutyPlanCard: View {
    let event: AgoraEvent
    @Environment(AppStore.self) private var store
    @Environment(ToastCenter.self) private var toasts
    @State private var runner = ActionRunner()
    @State private var expanded = false
    @State private var newTask = ""
    @State private var addingTask = false
    @State private var assigning: String?
    @State private var deletingRole: String?

    private var canManage: Bool { event.canEdit || event.duties.contains(where: \.canManageDuty) }

    private var groups: [(role: String, duties: [Duty])] {
        var order: [String] = []
        var map: [String: [Duty]] = [:]
        for duty in event.duties {
            if map[duty.role] == nil { order.append(duty.role) }
            map[duty.role, default: []].append(duty)
        }
        return order.map { ($0, map[$0] ?? []) }
    }

    var body: some View {
        let filled = event.duties.filter(\.isFilled).count
        VStack(alignment: .leading, spacing: 12) {
            Button {
                withAnimation(.snappy) { expanded.toggle() }
            } label: {
                HStack(spacing: 12) {
                    IconTile(systemImage: "list.clipboard", color: Palette.indigo, size: 38)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Dienstplan").font(.system(size: 16, weight: .heavy)).foregroundStyle(Palette.text)
                        Text(event.duties.isEmpty ? String(localized: "Noch keine Aufgaben")
                             : String(localized: "\(filled) von \(event.duties.count) besetzt · \(groups.count) Aufgaben"))
                            .font(.system(size: 13)).foregroundStyle(Palette.textSecondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.down").font(.system(size: 13, weight: .bold)).foregroundStyle(Palette.textSecondary)
                        .rotationEffect(.degrees(expanded ? 180 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if !event.duties.isEmpty {
                CapsuleProgress(value: Double(filled) / Double(max(event.duties.count, 1)),
                                fill: filled == event.duties.count ? Palette.button
                                    : LinearGradient(colors: [Color(hex: 0x818CF8), Color(hex: 0x6366F1)], startPoint: .leading, endPoint: .trailing))
            }
            if expanded {
                if event.duties.isEmpty {
                    Text(event.canEdit ? "Lege Aufgaben an und frage Personen oder Gruppen dafür an." : "Für dieses Event sind keine Dienste eingetragen.")
                        .font(.system(size: 14)).foregroundStyle(Palette.textSecondary)
                }
                ForEach(groups, id: \.role) { group in
                    Hairline()
                    roleRow(group.role, group.duties)
                }
                if event.canEdit {
                    Button { newTask = ""; addingTask = true } label: {
                        Label("Aufgabe hinzufügen", systemImage: "plus")
                            .font(.system(size: 14.5, weight: .bold))
                            .foregroundStyle(Palette.textSecondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 11)
                            .overlay(RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                                .strokeBorder(Palette.border, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .card()
        .disabled(runner.busy)
        .alert("Aufgabe hinzufügen", isPresented: $addingTask) {
            TextField("Name der Aufgabe", text: $newTask)
            Button("Abbrechen", role: .cancel) {}
            Button("Hinzufügen") { addTask() }
        }
        .sheet(item: Binding(get: { assigning.map(RoleRef.init) }, set: { assigning = $0?.role })) { ref in
            AssignDutySheet(event: event, role: ref.role)
        }
        .confirmationDialog(deletingRole.map { "Möchtest du die gesamte Aufgabe „\($0)“ mit allen Einträgen wirklich löschen?" } ?? "",
                            isPresented: Binding(get: { deletingRole != nil }, set: { if !$0 { deletingRole = nil } }), titleVisibility: .visible) {
            Button("Löschen", role: .destructive) { if let role = deletingRole { deleteRole(role) } }
        }
    }

    private func roleRow(_ role: String, _ duties: [Duty]) -> some View {
        let assignees = duties.filter(\.hasAssignee)
        let hasOpen = assignees.isEmpty || assignees.count < duties.count
        let me = store.user?.userId ?? ""
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(role).font(.system(size: 15, weight: .heavy)).foregroundStyle(Palette.text)
                Spacer()
                if canManage {
                    if !hasOpen {
                        toolButton("plus", label: "Weitere Person anfragen") { assigning = role }
                    }
                    if event.canEdit {
                        toolButton("trash", label: "Aufgabe löschen") { deletingRole = role }
                    }
                }
            }
            FlowLayout(spacing: 6) {
                ForEach(assignees) { duty in chip(duty, me: me, isLast: duties.count == 1) }
                if hasOpen {
                    Button { if canManage { assigning = role } else { claim(duties.first(where: \.isOpen)) } } label: {
                        Label(canManage ? "Offen – zuweisen" : "Offen", systemImage: "plus")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(Palette.textSecondary)
                            .padding(.horizontal, 10)
                            .frame(height: 30)
                            .overlay(Capsule().strokeBorder(Palette.border, style: StrokeStyle(lineWidth: 1.2, dash: [4, 3])))
                    }
                    .buttonStyle(.plain)
                    .disabled(!canManage && duties.first(where: \.isOpen) == nil)
                }
            }
            ForEach(duties.filter { $0.requestedUser == me && $0.isRequested }) { duty in
                HStack {
                    Text("Du wurdest angefragt").font(.system(size: 13.5, weight: .bold)).foregroundStyle(Palette.amberText)
                    Spacer()
                    Button("Zusagen") { respond(duty, true) }.buttonStyle(.agoraPrimary(small: true, fullWidth: false))
                    Button("Ablehnen") { respond(duty, false) }.buttonStyle(.agoraSecondary(small: true, fullWidth: false))
                }
                .padding(10)
                .background(Palette.warning.opacity(0.08), in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
            }
            ForEach(duties.filter { !$0.notes.isEmpty }) { duty in
                Label(duty.notes, systemImage: "note.text").font(.system(size: 13)).foregroundStyle(Palette.textSecondary)
            }
        }
    }

    private func toolButton(_ icon: String, label: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Palette.textSecondary)
                .frame(width: 30, height: 30)
                .background(Palette.surfaceAlt, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private func chip(_ duty: Duty, me: String, isLast: Bool) -> some View {
        let isMe = duty.assignedUser == me || duty.requestedUser == me
        let name = isMe ? String(localized: "Du") : (duty.isGroup && duty.assignedUser.isEmpty ? duty.groupName : duty.personName)
        let color: Color = duty.isDeclined ? Palette.danger : (duty.isRequested ? Palette.warning : (duty.isGroup && duty.assignedUser.isEmpty ? Palette.indigo : Palette.success))
        return HStack(spacing: 6) {
            if duty.isGroup && duty.assignedUser.isEmpty {
                Image(systemName: "person.3.fill").font(.system(size: 11)).foregroundStyle(color)
            } else {
                Avatar(userId: duty.assignedUser.isEmpty ? duty.requestedUser : duty.assignedUser, name: name, size: 22)
            }
            Text(name).font(.system(size: 13, weight: .bold)).strikethrough(duty.isDeclined).foregroundStyle(Palette.text)
            if duty.isConfirmed { Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)).foregroundStyle(Palette.success) }
            if duty.isRequested { Text("angefragt").font(.system(size: 11.5, weight: .semibold)).foregroundStyle(Palette.amberText) }
            if duty.isDeclined { Text("abgelehnt").font(.system(size: 11.5, weight: .semibold)).foregroundStyle(Palette.danger) }
            if canManage || duty.canManageDuty {
                Button { removeEntry(duty, isLast: isLast) } label: {
                    Image(systemName: "xmark").font(.system(size: 10, weight: .bold)).foregroundStyle(Palette.textSecondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(name) entfernen")
            } else if duty.assignedUser == me && duty.isConfirmed {
                Button { unclaim(duty) } label: {
                    Image(systemName: "xmark").font(.system(size: 10, weight: .bold)).foregroundStyle(Palette.textSecondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Austragen")
            }
        }
        .padding(.leading, 4)
        .padding(.trailing, 10)
        .frame(height: 30)
        .background(color.opacity(0.08), in: Capsule())
        .overlay(Capsule().strokeBorder(color.opacity(0.3), lineWidth: 1))
    }

    private func respond(_ duty: Duty, _ accept: Bool) {
        runner.run(toasts, success: accept ? String(localized: "Dienst zugesagt") : String(localized: "Dienst abgelehnt")) {
            try await store.repository.respondToDuty(id: duty.id, accept: accept)
            await store.refreshEvents()
        }
    }

    private func claim(_ duty: Duty?) {
        guard let duty else { return }
        runner.run(toasts, success: String(localized: "Eingetragen")) {
            try await store.repository.claimDuty(id: duty.id, claim: true)
            await store.refreshEvents()
        }
    }

    private func unclaim(_ duty: Duty) {
        runner.run(toasts, success: String(localized: "Ausgetragen")) {
            try await store.repository.claimDuty(id: duty.id, claim: false)
            await store.refreshEvents()
        }
    }

    /// Removing the last entry of a task keeps the task as an empty slot.
    private func removeEntry(_ duty: Duty, isLast: Bool) {
        runner.run(toasts, success: String(localized: "Entfernt")) {
            if isLast { try await store.repository.addDuty(eventId: event.id, roleName: duty.role) }
            try await store.repository.deleteDuty(id: duty.id)
            await store.refreshEvents()
        }
    }

    private func addTask() {
        let name = newTask.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        runner.run(toasts, success: String(localized: "Aufgabe „\(name)“ hinzugefügt!")) {
            try await store.repository.addDuty(eventId: event.id, roleName: name)
            await store.refreshEvents()
        }
    }

    private func deleteRole(_ role: String) {
        let duties = event.duties.filter { $0.role == role }
        runner.run(toasts, success: String(localized: "Aufgabe gelöscht")) {
            for duty in duties { try await store.repository.deleteDuty(id: duty.id) }
            await store.refreshEvents()
        }
    }
}

struct RoleRef: Identifiable {
    let role: String
    var id: String { role }
}

/// "Person oder Gruppe zuweisen": ask a person or assign a group to a task.
struct AssignDutySheet: View {
    let event: AgoraEvent
    let role: String
    @Environment(AppStore.self) private var store
    @Environment(ToastCenter.self) private var toasts
    @Environment(\.dismiss) private var dismiss
    @State private var candidates = Candidates()
    @State private var loading = true
    @State private var kind = 0
    @State private var query = ""
    @State private var runner = ActionRunner()

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
                if loading {
                    ProgressView().frame(maxWidth: .infinity)
                } else if kind == 0 {
                    ForEach(candidates.candidates.filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) }) { person in
                        HStack {
                            Avatar(userId: person.id, name: person.name, size: 32)
                            VStack(alignment: .leading) {
                                Text(person.name)
                                if !person.email.isEmpty { Text(person.email).font(.caption).foregroundStyle(Palette.textSecondary) }
                            }
                            Spacer()
                            Button("Anfragen") { assign(userId: person.id, groupId: nil) }.buttonStyle(.borderless).bold()
                        }
                    }
                } else {
                    ForEach(candidates.groups.filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) }) { group in
                        HStack {
                            IconTile(systemImage: "person.3.fill", color: Palette.indigo, size: 32)
                            VStack(alignment: .leading) {
                                Text(group.name)
                                Text("Gruppe fest einteilen").font(.caption).foregroundStyle(Palette.textSecondary)
                            }
                            Spacer()
                            Button("Zuweisen") { assign(userId: nil, groupId: group.id) }.buttonStyle(.borderless).bold()
                        }
                    }
                }
            }
            .searchable(text: $query, prompt: Text(kind == 0 ? "Person suchen…" : "Gruppe suchen…"))
            .disabled(runner.busy)
            .navigationTitle("Person oder Gruppe zuweisen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } } }
            .safeAreaInset(edge: .top) {
                Text("Aufgabe: \(role)").font(.subheadline.weight(.semibold)).foregroundStyle(Palette.textSecondary)
                    .frame(maxWidth: .infinity).padding(.vertical, 6).background(.bar)
            }
        }
        .task {
            candidates = (try? await store.repository.candidates()) ?? Candidates()
            loading = false
        }
    }

    private func assign(userId: String?, groupId: String?) {
        let slot = event.duties.first { $0.role == role && $0.status == "open" }
        runner.run(toasts, success: userId != nil ? String(localized: "Dienstanfrage versendet!") : String(localized: "Gruppe erfolgreich eingeteilt!")) {
            if let slot {
                try await store.repository.assignDuty(id: slot.id, userId: userId, groupId: groupId)
            } else {
                try await store.repository.addDuty(eventId: event.id, roleName: role, userId: userId, groupId: groupId)
            }
            await store.refreshEvents()
        } done: {
            dismiss()
        }
    }
}
