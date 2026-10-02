import SwiftUI

/// Start page: welcome, payment status, duty requests, own duties and new messages.
struct HomeView: View {
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router

    var body: some View {
        TabPage {
            if let user = store.user {
                HeroCard(user: user)
                if !store.data.loaded && store.data.ownPerson == nil {
                    LoadingCard()
                } else {
                    Button { router.select(.finances) } label: {
                        FinanceStatusCard(user: user, person: store.data.ownPerson)
                    }
                    .buttonStyle(.pressable)
                    .accessibilityHint("Öffnet die Finanzen")
                }
                if !store.data.dutyRequests.isEmpty { DutyRequestCard() }
                let unread = store.data.unreadThreads
                if !unread.isEmpty { NewMessagesCard(threads: unread) }
                let duties = EventRules.myDutyEvents(store.data.events, user: user, today: Day.today())
                if !duties.isEmpty {
                    Text("Deine Dienste").font(.agoraSection).foregroundStyle(Palette.text).padding(.top, 4)
                        .accessibilityAddTraits(.isHeader)
                    ForEach(duties) { event in
                        Button { router.open(.event(event.id)) } label: { EventRow(event: event) }
                            .buttonStyle(.pressable)
                    }
                }
            }
        }
    }
}

/// Gradient welcome card with decorative circles (`.hero-card`).
struct HeroCard: View {
    let user: User

    var body: some View {
        VStack(spacing: 8) {
            Text("Willkommen")
                .font(.system(size: 12, weight: .bold))
                .textCase(.uppercase)
                .tracking(0.6)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(.black.opacity(0.15), in: Capsule())
            Text(user.fullName)
                .font(.system(size: 34, weight: .heavy))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.6)
            if !user.email.isEmpty {
                Text(user.email).font(.system(size: 15, weight: .medium)).opacity(0.9)
            }
        }
        .foregroundStyle(.white)
        .padding(.vertical, 24)
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity)
        .background {
            ZStack {
                Palette.brand
                Circle().fill(.white.opacity(0.1)).frame(width: 150, height: 150).offset(x: -50, y: -50)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                Circle().fill(.white.opacity(0.15)).frame(width: 100, height: 100).offset(x: 20, y: 20)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: Radius.hero, style: .continuous))
        .shadow(color: Color(hex: 0x06B6D4, opacity: 0.25), radius: 12, y: 6)
        .accessibilityElement(children: .combine)
    }
}

/// Placeholder while the first data loads.
struct LoadingCard: View {
    var body: some View {
        HStack(spacing: 12) {
            ProgressView().tint(Palette.primary)
            Text("Lade Daten…").font(.system(size: 15, weight: .semibold)).foregroundStyle(Palette.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .card(padding: 24)
    }
}

/// "Neue Nachrichten": unread conversations with a jump to all chats (`.home-msg-card`).
struct NewMessagesCard: View {
    @Environment(Router.self) private var router
    let threads: [MentoringThread]
    private let rows = 3

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                IconTile(systemImage: "bubble.left.and.bubble.right", color: Palette.violet, size: 34)
                Text("Neue Nachrichten").font(.system(size: 16, weight: .heavy)).foregroundStyle(Palette.text)
                CountBadge(count: threads.reduce(0) { $0 + $1.unreadCount }, color: Palette.violet)
                Spacer(minLength: 0)
                Button { router.select(.mentoring) } label: {
                    HStack(spacing: 2) {
                        Text("Alle")
                        Image(systemName: "chevron.right").font(.system(size: 11, weight: .bold))
                    }
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Palette.primary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 10)
            ForEach(threads.prefix(rows)) { thread in
                Hairline()
                Button { router.open(.chat(thread.id)) } label: { row(thread) }
                    .buttonStyle(.pressable)
            }
            if threads.count > rows {
                Hairline()
                Text("+\(threads.count - rows) weitere ungelesene Unterhaltungen")
                    .font(.system(size: 13)).foregroundStyle(Palette.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
            }
        }
        .card(padding: 0)
    }

    private func row(_ thread: MentoringThread) -> some View {
        HStack(spacing: 12) {
            Avatar(userId: thread.partnerPictureUserId, name: thread.partnerName, size: 44, anonymous: thread.iAmMentor)
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(thread.partnerName).font(.system(size: 15, weight: .heavy)).foregroundStyle(Palette.text).lineLimit(1)
                    Spacer(minLength: 6)
                    Text(Formats.chatTime(thread.lastActivity)).font(.system(size: 12, weight: .bold)).foregroundStyle(Palette.primary)
                }
                CapsLabel(thread.iAmMentor ? "Suchender (anonym)" : "Dein Mentor")
                HStack {
                    Text(thread.lastMessage?.text.isEmpty == false ? thread.lastMessage!.text : String(localized: "Neue vertrauliche Nachricht"))
                        .font(.system(size: 14.5)).foregroundStyle(Palette.text).lineLimit(1)
                    Spacer(minLength: 6)
                    CountBadge(count: thread.unreadCount)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}
