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
                    Text("Anmeldung").font(.system(size: 16, weight: .bold)).foregroundStyle(Palette.text)
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

    /// Guests (signed up without an account through the shared link) are marked; editors see how to reach them.
    private func attendeeRow(_ attendee: Attendee, waiting: Bool) -> some View {
        HStack(spacing: 10) {
            Avatar(userId: attendee.pictureUserId, name: attendee.name, size: 32)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(attendee.name).font(.system(size: 15, weight: .semibold)).foregroundStyle(waiting ? Palette.amberText : Palette.text)
                        .lineLimit(1)
                    if attendee.guest { StatusPill(text: String(localized: "Gast"), color: Palette.primary) }
                }
                if attendee.guest && !attendee.email.isEmpty {
                    let contact = [attendee.email, attendee.age.map { String(localized: "Alter \($0)") }].compactMap { $0 }.joined(separator: " · ")
                    if let mail = URL(string: "mailto:\(attendee.email)") {
                        Link(contact, destination: mail)
                            .font(.system(size: 13))
                            .foregroundStyle(Palette.textSecondary)
                            .lineLimit(1)
                            .accessibilityHint("E-Mail schreiben")
                    } else {
                        Text(contact).font(.system(size: 13)).foregroundStyle(Palette.textSecondary).lineLimit(1)
                    }
                }
            }
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
                Avatar(userId: person.pictureUserId, name: person.name, size: 28)
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
