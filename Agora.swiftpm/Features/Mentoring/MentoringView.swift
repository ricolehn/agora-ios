import SwiftUI

/// Mentoring: conversations, finding mentors, applications (managers).
struct MentoringView: View {
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router
    @State private var tab: Tab = .messages
    @State private var filter = ""
    @State private var mentors: [Mentor] = []
    @State private var mentorsLoaded = false
    @State private var applicationFilter = "pending"
    @State private var applications: [Mentor] = []
    @State private var profileSheet = false
    @State private var contacting: Mentor?

    enum Tab: Hashable { case messages, find, applications }

    var body: some View {
        TabPage(refresh: { await refresh() }) {
            header
            PillTabs(items: tabs, selection: $tab)
            switch tab {
            case .messages: messages
            case .find: findMentors
            case .applications: ApplicationsList(filter: $applicationFilter, applications: applications) { await loadApplications() }
            }
        }
        .task(id: tab) {
            if tab == .find { await loadMentors() }
            if tab == .applications { await loadApplications() }
        }
        .onChange(of: store.changeTick) { _, _ in
            guard !store.changedAreas.isDisjoint(with: ["all", "mentoring"]) else { return }
            Task {
                if tab == .find { await loadMentors() }
                if tab == .applications { await loadApplications() }
            }
        }
        .onChange(of: applicationFilter) { _, _ in Task { await loadApplications() } }
        .sheet(isPresented: $profileSheet) { MentorProfileSheet() }
        .sheet(item: $contacting) { mentor in ContactMentorSheet(mentor: mentor) }
    }

    private var tabs: [PillTabs<Tab>.Item] {
        var items: [PillTabs<Tab>.Item] = [
            .init(value: .messages, title: "Nachrichten", badge: store.data.unreadThreads.count),
            .init(value: .find, title: "Mentoren finden")
        ]
        if store.user?.managesMentoring == true { items.append(.init(value: .applications, title: "Bewerbungen")) }
        return items
    }

    private var header: some View {
        let profile = store.data.mentorProfile
        let title: LocalizedStringKey = profile.exists && profile.isPending ? "⏳ Bewerbung in Prüfung"
            : (profile.isApproved ? "Mein Mentoren-Profil" : "Als Mentor bewerben")
        return VStack(spacing: 10) {
            Text("Mentoring").font(.system(size: 22, weight: .heavy)).foregroundStyle(Palette.text)
            Text("Persönliche Begleitung, offene Ohren & anonyme Gespräche")
                .font(.system(size: 14)).foregroundStyle(Palette.textSecondary).multilineTextAlignment(.center)
            Button { profileSheet = true } label: {
                Text(title)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 26)
                    .padding(.vertical, 11)
                    .frame(minWidth: 210)
                    .background(Palette.button, in: Capsule())
                    .shadow(color: Color(hex: 0x06B6D4, opacity: 0.35), radius: 9, y: 4)
            }
            .buttonStyle(.pressable)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .card(padding: 20)
    }

    // MARK: Conversations

    @ViewBuilder
    private var messages: some View {
        let threads = store.data.threads
            .filter { filter.isEmpty || $0.partnerName.localizedCaseInsensitiveContains(filter) }
            .sorted { $0.lastActivity > $1.lastActivity }
        SearchField(placeholder: "Kontakte filtern…", text: $filter)
        if threads.isEmpty {
            EmptyState(systemImage: "bubble.left.and.bubble.right", title: "Noch keine Gespräche",
                       message: "Finde einen Mentor und beginne ein anonymes Gespräch.").card(padding: 0)
        } else {
            ForEach(threads) { thread in
                Button { router.open(.chat(thread.id)) } label: { ThreadRow(thread: thread) }
                    .buttonStyle(.pressable)
            }
        }
    }

    // MARK: Find mentors

    @ViewBuilder
    private var findMentors: some View {
        if !mentorsLoaded {
            LoadingCard()
        } else if mentors.isEmpty {
            EmptyState(systemImage: "person.2", title: "Aktuell sind keine Mentoren verfügbar").card(padding: 0)
        } else {
            ForEach(mentors) { mentor in
                MentorCard(mentor: mentor,
                           thread: store.data.threads.first { $0.mentor == mentor.user && !$0.iAmMentor },
                           onContact: { contacting = mentor },
                           onEditProfile: { profileSheet = true })
            }
        }
    }

    private func refresh() async {
        await store.refreshAll(showIndicator: true)
        if tab == .find { await loadMentors() }
        if tab == .applications { await loadApplications() }
    }

    private func loadMentors() async {
        if let list = try? await store.repository.mentors() { mentors = list }
        mentorsLoaded = true
    }

    private func loadApplications() async {
        applications = (try? await store.repository.mentors(status: applicationFilter)) ?? []
    }
}

/// Conversation card with avatar (anonymous for mentors), state dot, role, preview and unread count.
struct ThreadRow: View {
    let thread: MentoringThread

    var body: some View {
        let unread = thread.unreadCount > 0
        HStack(spacing: 14) {
            Avatar(userId: thread.partnerPictureUserId, name: thread.partnerName, size: 46, anonymous: thread.iAmMentor)
                .overlay(alignment: .bottomTrailing) {
                    Circle().fill(thread.isClosed ? Palette.slate : Palette.success)
                        .frame(width: 12, height: 12)
                        .overlay(Circle().strokeBorder(Palette.surface, lineWidth: 2))
                }
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(thread.partnerName).font(.system(size: 15.5, weight: unread ? .heavy : .bold)).foregroundStyle(Palette.text).lineLimit(1)
                    if thread.isClosed { Image(systemName: "lock.fill").font(.system(size: 11)).foregroundStyle(Palette.slate) }
                    Spacer(minLength: 6)
                    Text(Formats.chatTime(thread.lastActivity)).font(.system(size: 12, weight: .medium)).foregroundStyle(Palette.textSecondary)
                }
                Text(thread.iAmMentor ? "Suchender (anonym)" : "Dein Mentor")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(thread.isClosed ? Palette.slate : (thread.iAmMentor ? Palette.textSecondary : Palette.primaryDark))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background((thread.iAmMentor ? Palette.slate : Palette.primary).opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
                HStack {
                    Text(thread.lastMessage?.text.nilIfEmpty ?? (thread.iAmMentor ? String(localized: "Suchender (anonym)") : String(localized: "Dein Mentor")))
                        .font(.system(size: 14, weight: unread ? .semibold : .regular))
                        .foregroundStyle(unread ? Palette.text : Palette.textSecondary)
                        .lineLimit(1)
                    Spacer(minLength: 6)
                    if unread { CountBadge(count: thread.unreadCount, color: Palette.success) }
                }
            }
        }
        .padding(.vertical, 13)
        .padding(.horizontal, 16)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.list, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.list, style: .continuous)
            .strokeBorder(unread ? Palette.primary.opacity(0.35) : Palette.borderLight, lineWidth: 1))
        .shadow(color: unread ? Palette.primary.opacity(0.1) : Palette.shadow, radius: 7, y: 4)
        .accessibilityElement(children: .combine)
    }
}

/// Mentor with ring, bio and the matching action.
struct MentorCard: View {
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router
    let mentor: Mentor
    let thread: MentoringThread?
    let onContact: () -> Void
    let onEditProfile: () -> Void

    var body: some View {
        let isMe = mentor.user == store.user?.userId
        let showCapacity = isMe || store.user?.managesMentoring == true
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                Avatar(userId: mentor.user, name: mentor.displayName, size: 52, ring: mentor.status == "approved" ? .mentor : nil)
                VStack(alignment: .leading, spacing: 3) {
                    Text(mentor.displayName).font(.system(size: 17, weight: .bold)).foregroundStyle(Palette.text)
                    Label("Geprüfter Mentor", systemImage: "checkmark.seal.fill")
                        .font(.system(size: 12.5, weight: .bold)).foregroundStyle(Palette.primaryDark)
                }
            }
            if !mentor.bio.isEmpty {
                Text(mentor.bio)
                    .font(.system(size: 14.5))
                    .foregroundStyle(Palette.text)
                    .lineSpacing(2)
                    .padding(.vertical, 12)
                    .padding(.horizontal, 14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Palette.surfaceAlt, in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: Radius.control, style: .continuous).strokeBorder(Palette.borderLight, lineWidth: 1))
            }
            HStack {
                if showCapacity {
                    Text("👥 \(mentor.activeMentees) / \(mentor.maxMentees) aktiv").font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.textSecondary)
                }
                Spacer()
                if isMe {
                    Button("Profil bearbeiten", action: onEditProfile).buttonStyle(.agoraSecondary(small: true, fullWidth: false))
                } else if let thread {
                    Button { router.open(.chat(thread.id)) } label: { Label("Zum Gespräch", systemImage: "bubble.left") }
                        .buttonStyle(.agoraSecondary(small: true, fullWidth: false))
                } else if mentor.isFull || !mentor.isAccepting {
                    Text("Voll belegt").font(.system(size: 13, weight: .bold)).foregroundStyle(Palette.danger)
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(Palette.danger.opacity(0.1), in: Capsule())
                } else {
                    Button("Anonym kontaktieren", action: onContact)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 9)
                        .background(Palette.button, in: Capsule())
                }
            }
        }
        .card(radius: Radius.large, padding: 20)
    }
}

/// Managers: mentor applications by state, approve or reject.
struct ApplicationsList: View {
    @Environment(AppStore.self) private var store
    @Environment(ToastCenter.self) private var toasts
    @Binding var filter: String
    let applications: [Mentor]
    let reload: () async -> Void
    @State private var runner = ActionRunner()

    var body: some View {
        Picker("Filter", selection: $filter) {
            Text("Ausstehend").tag("pending")
            Text("Freigegeben").tag("approved")
            Text("Abgelehnt").tag("rejected")
            Text("Alle").tag("all")
        }
        .pickerStyle(.segmented)
        if applications.isEmpty {
            EmptyState(systemImage: "person.badge.clock", title: "Keine Bewerbungen").card(padding: 0)
        } else {
            ForEach(applications) { mentor in
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(mentor.displayName).font(.system(size: 16, weight: .bold)).foregroundStyle(Palette.text)
                            if let email = mentor.userEmail, !email.isEmpty {
                                Text(email).font(.system(size: 13)).foregroundStyle(Palette.textSecondary)
                            }
                        }
                        Spacer()
                        StatusPill(text: statusLabel(mentor.status), color: statusColor(mentor.status))
                    }
                    if !mentor.bio.isEmpty { Text(mentor.bio).font(.system(size: 14)).foregroundStyle(Palette.text) }
                    HStack(spacing: 8) {
                        if mentor.status != "approved" {
                            Button("Genehmigen") { set(mentor, "approved") }.buttonStyle(.agoraPrimary(small: true))
                        }
                        if mentor.status != "rejected" {
                            Button("Ablehnen") { set(mentor, "rejected") }.buttonStyle(.agoraDanger(small: true))
                        }
                    }
                    .disabled(runner.busy)
                }
                .card(radius: Radius.list)
            }
        }
    }

    private func statusLabel(_ status: String) -> String {
        switch status {
        case "approved": return String(localized: "Freigegeben")
        case "rejected": return String(localized: "Abgelehnt")
        default: return String(localized: "Ausstehend")
        }
    }

    private func statusColor(_ status: String) -> Color {
        status == "approved" ? Palette.success : (status == "rejected" ? Palette.danger : Palette.warning)
    }

    private func set(_ mentor: Mentor, _ status: String) {
        runner.run(toasts, success: String(localized: "Gespeichert")) {
            try await store.repository.setMentorStatus(recordId: mentor.id, status)
            await reload()
        }
    }
}

/// Apply as mentor or edit the own mentor profile.
struct MentorProfileSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(ToastCenter.self) private var toasts
    @Environment(\.dismiss) private var dismiss
    @State private var action = FormAction()
    @State private var bio = ""
    @State private var maxMentees = 3
    @State private var accepting = true

    private var profile: MentorProfile? { store.data.mentorProfile.mentor }
    private var isNew: Bool { !store.data.mentorProfile.exists }

    var body: some View {
        FormSheet(title: isNew ? "Als Mentor bewerben" : "Mein Mentoren-Profil", confirm: isNew ? "Bewerbung absenden" : "Speichern",
                  canConfirm: !bio.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, busy: action.busy, error: action.error, onConfirm: save) {
            if let profile, profile.status == "pending" {
                Section { Label("Deine Bewerbung wird geprüft.", systemImage: "hourglass").foregroundStyle(Palette.amberText) }
            }
            Section {
                TextField("Erzähl kurz von dir und warum du begleiten möchtest", text: $bio, axis: .vertical)
                    .lineLimit(4...10)
            } header: {
                Text("Über mich & Motivation")
            }
            Section {
                Stepper("Kapazität: \(maxMentees)", value: $maxMentees, in: 1...20)
                if !isNew { Toggle("Nimmt neue Gespräche an", isOn: $accepting) }
            } footer: {
                Text("Wie viele Personen du gleichzeitig begleiten kannst.")
            }
        }
        .onAppear {
            if let profile {
                bio = profile.bio
                maxMentees = max(profile.maxMentees, 1)
                accepting = profile.isAccepting
            }
        }
    }

    private func save() {
        let new = isNew
        action.run(toasts: toasts, success: new ? String(localized: "Bewerbung eingereicht") : String(localized: "Gespeichert"), dismiss: dismiss) {
            try await store.repository.saveMentorProfile(isNew: new, bio: bio, maxMentees: maxMentees, isAccepting: accepting)
            await store.refreshAll()
        }
    }
}

/// First anonymous message to a mentor; opens the new conversation.
struct ContactMentorSheet: View {
    let mentor: Mentor
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router
    @Environment(ToastCenter.self) private var toasts
    @Environment(\.dismiss) private var dismiss
    @State private var action = FormAction()
    @State private var message = ""

    var body: some View {
        FormSheet(title: "Mentor kontaktieren", confirm: "Senden", canConfirm: !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  busy: action.busy, error: action.error, onConfirm: send) {
            Section {
                Label("Deine erste Nachricht an \(mentor.displayName). Du bleibst anonym.", systemImage: "lock.shield")
                    .font(.subheadline)
                    .foregroundStyle(Color(hex: 0x0284C7))
                    .listRowBackground(Color(hex: 0x0EA5E9, opacity: 0.08))
            }
            Section("Deine Nachricht") {
                TextField("Worum geht es?", text: $message, axis: .vertical).lineLimit(4...10)
            }
        }
    }

    private func send() {
        let text = message.trimmingCharacters(in: .whitespacesAndNewlines)
        action.run(toasts: toasts, success: String(localized: "Nachricht gesendet"), dismiss: dismiss) {
            let threadId = try await store.repository.contactMentor(userId: mentor.user, message: text)
            await store.refreshAll()
            if !threadId.isEmpty { router.open(.chat(threadId)) }
        }
    }
}
