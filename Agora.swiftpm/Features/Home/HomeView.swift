import SwiftUI

/// Start page for members like the web app (beta16): short greeting, an overdue payment right below it, duty
/// requests, "Als Nächstes" (the next five appointments and events as a swipeable row), own duties, new messages
/// and, when a payment is due soon, a slim line at the end. While everything is paid the payment state is hidden.
struct HomeView: View {
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router
    @State private var openRequest: FinanceRequest?
    private let upcomingCount = 5
    private let requestRows = 3

    var body: some View {
        TabPage(spacing: 22) {
            if let user = store.user {
                HomeGreeting(user: user)
                let person = user.pays ? store.data.ownPerson : nil
                if let person, person.statusMeta.isOverdue {
                    HomePaymentLine(person: person, overdue: true)
                }
                if !store.data.dutyRequests.isEmpty { DutyRequestCard() }
                // Treasurers and the owner: open requests right after the duty requests (web beta18)
                if !store.data.pendingRequests.isEmpty {
                    // Without the finance tab view (owner only) all requests show here
                    let toFinances = user.viewsFinances
                    let showAll: (() -> Void)? = toFinances ? { router.select(.finances) } : nil
                    OpenRequestsCard(requests: store.data.pendingRequests, limit: toFinances ? requestRows : .max,
                                     onAll: showAll) {
                        openRequest = $0
                    }
                }
                if !store.data.loaded && store.data.events.isEmpty {
                    LoadingCard()
                } else {
                    upcoming
                }
                let duties = EventRules.myDutyEvents(store.data.events.filter { !$0.isCancelled }, user: user, today: Day.today())
                let unread = store.data.unreadThreads
                if !duties.isEmpty && !unread.isEmpty {
                    // iPad: own duties and new messages side by side
                    TwoPane(spacing: 22) {
                        dutiesSection(duties, minWidth: .infinity)
                    } right: {
                        NewMessagesCard(threads: unread)
                    }
                } else if !duties.isEmpty {
                    dutiesSection(duties, minWidth: 380)
                } else if !unread.isEmpty {
                    NewMessagesCard(threads: unread)
                }
                if let person, !person.statusMeta.isOverdue, person.statusMeta.isSoonDue {
                    HomePaymentLine(person: person, overdue: false)
                }
            }
        }
        .sheet(item: $openRequest) { request in
            RequestDetailSheet(request: request, canDecide: store.user.map { $0.managesFinances || $0.owner } ?? false)
        }
    }

    /// Own duties; on iPad as columns of cards at least [minWidth] wide (one column next to the messages).
    private func dutiesSection(_ duties: [AgoraEvent], minWidth: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HomeSectionHead(title: "Deine Dienste")
            AdaptiveGrid(minWidth: minWidth) {
                ForEach(duties) { event in
                    Button { router.open(.event(event.id)) } label: { EventRow(event: event) }
                        .buttonStyle(.pressable)
                }
            }
        }
    }

    /// "Als Nächstes": the next appointments and events (also open registrations), side by side.
    private var upcoming: some View {
        let today = Day.today()
        let start: (AgoraEvent) -> String = { $0.date < today ? today : $0.date }
        let events = store.data.events
            .filter { !$0.date.isEmpty && !$0.isCancelled && !$0.isPast(today: today) }
            .sorted { start($0) == start($1) ? $0.startTime < $1.startTime : start($0) < start($1) }
            .prefix(upcomingCount)
        return UpcomingRow(events: Array(events), today: today)
    }
}

/// The "Als Nächstes" row; reads the page width, so it lives inside TabPage.
struct UpcomingRow: View {
    @Environment(Router.self) private var router
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.pageContentWidth) private var contentWidth
    @Environment(\.pageGutter) private var gutter
    let events: [AgoraEvent]
    let today: String

    var body: some View {
        // iPad: five cards share the width (at least 236pt each), otherwise the row scrolls on to the right
        let cardWidth: CGFloat = sizeClass == .regular ? max(236, (contentWidth - 4 * 12) / 5) : 236
        VStack(alignment: .leading, spacing: 10) {
            HomeSectionHead(title: "Als Nächstes", link: events.isEmpty ? nil : "Alle") { router.openTermine() }
            if events.isEmpty {
                Text("Gerade steht nichts an – genieß die freie Zeit! 🌿")
                    .font(.system(size: 14.5))
                    .foregroundStyle(Palette.textSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(18)
                    .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.large, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: Radius.large, style: .continuous)
                        .strokeBorder(Palette.border, style: StrokeStyle(lineWidth: 1, dash: [5, 4])))
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    // All cards as tall as the tallest one of these events, the chip at the bottom: a fixed height for
                    // the worst case (two-line title, place and chip) left empty space under most cards
                    HStack(alignment: .top, spacing: 12) {
                        ForEach(events) { event in
                            Button { router.open(.event(event.id)) } label: { NextCard(event: event, today: today, width: cardWidth) }
                                .buttonStyle(.pressable)
                        }
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    .scrollTargetLayout()
                    .padding(.horizontal, gutter)
                    .padding(.bottom, 6)
                }
                .scrollTargetBehavior(.viewAligned)
                // The row would cut the card shadows off at its edges
                .scrollClipDisabled()
                .padding(.horizontal, -gutter)
            }
        }
    }
}

/// "SAMSTAG, 3. OKTOBER" over "Hallo, Max 👋" (morning / day / evening).
struct HomeGreeting: View {
    let user: User

    var body: some View {
        let hour = Calendar.current.component(.hour, from: Date())
        let hello = hour < 11 ? String(localized: "Guten Morgen") : (hour < 18 ? String(localized: "Hallo") : String(localized: "Guten Abend"))
        let first = (user.firstName.isEmpty ? user.fullName : user.firstName).trimmingCharacters(in: .whitespaces)
            .split(separator: " ").first.map(String.init) ?? ""
        VStack(alignment: .leading, spacing: 4) {
            Text(Formats.greetingDate())
                .font(.system(size: 13, weight: .bold))
                .textCase(.uppercase)
                .tracking(0.6)
                .foregroundStyle(Palette.textSecondary)
            Text(first.isEmpty ? "\(hello) 👋" : "\(hello), \(first) 👋")
                .font(.system(size: 27, weight: .heavy))
                .tracking(-0.4)
                .foregroundStyle(Palette.text)
                .accessibilityAddTraits(.isHeader)
        }
        .padding(.top, 4)
        .padding(.leading, 2)
    }
}

/// Section heading of the start page with an optional link on the right ("Alle ›").
struct HomeSectionHead: View {
    let title: LocalizedStringKey
    var link: LocalizedStringKey?
    var action: () -> Void = {}

    var body: some View {
        HStack {
            Text(title).font(.system(size: 19, weight: .heavy)).tracking(-0.2).foregroundStyle(Palette.text)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 0)
            if let link {
                Button(action: action) {
                    HStack(spacing: 2) {
                        Text(link)
                        Image(systemName: "chevron.right").font(.system(size: 11, weight: .bold))
                    }
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Palette.primary)
                }
            }
        }
    }
}

/// Overdue: red card with the open amount and "Ansehen"; due soon: a slim amber line. Tapping opens the finances.
struct HomePaymentLine: View {
    @Environment(Router.self) private var router
    let person: Person
    let overdue: Bool

    var body: some View {
        let color = overdue ? Palette.danger : Palette.warning
        Button { router.select(.finances) } label: {
            HStack(spacing: 12) {
                Image(systemName: "exclamationmark")
                    .font(.system(size: 15, weight: .heavy))
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(color, in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(overdue ? Palette.danger : Palette.text)
                        .lineLimit(1)
                    Text(overdue ? String(localized: "\(Formats.money(person.overdueAmount)) offen") : person.statusMeta.text)
                        .font(.system(size: overdue ? 14 : 12.5, weight: overdue ? .bold : .regular))
                        .foregroundStyle(overdue ? Palette.text : Palette.textSecondary)
                }
                Spacer(minLength: 0)
                if overdue {
                    Text("Ansehen")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(color, in: Capsule())
                } else {
                    Image(systemName: "chevron.right").font(.system(size: 13, weight: .bold)).foregroundStyle(Palette.textSecondary)
                }
            }
            .padding(.horizontal, overdue ? 16 : 14)
            .padding(.vertical, overdue ? 14 : 12)
            .background(overdue ? Palette.danger.opacity(0.08) : Palette.surface, in: RoundedRectangle(cornerRadius: Radius.large, style: .continuous))
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.large, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Radius.large, style: .continuous).strokeBorder(color.opacity(0.35), lineWidth: overdue ? 1.5 : 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
        .accessibilityHint("Öffnet die Finanzen")
    }

    private var title: String {
        if overdue { return person.statusMeta.text.isEmpty ? String(localized: "Zahlung überfällig") : person.statusMeta.text }
        if person.standingOrderCovers { return String(localized: "Dauerauftrag aktiv") }
        return String(localized: "Bezahlt bis \(Formats.paidUntilMonth(person.paidUntil) ?? String(localized: "Nie"))")
    }
}

/// One card of the "Als Nächstes" row: picture or color mesh with the day on it, time, title, place, one chip.
struct NextCard: View {
    @Environment(AppStore.self) private var store
    let event: AgoraEvent
    let today: String
    /// 236pt on iPhone; on iPad wider so five cards share the width
    var width: CGFloat = 236

    var body: some View {
        let color = event.isPinned && !event.isTermin ? Palette.indigo : (event.isTermin ? Palette.slate : Palette.primary)
        let start = event.date < today ? today : event.date
        let isToday = start <= today
        // 16:9 picture; on wide cards it gets wider, not taller
        let coverHeight = min((width - 12) * 9 / 16, 200)
        VStack(alignment: .leading, spacing: 0) {
            Color.clear
                .frame(maxWidth: .infinity)
                .frame(height: coverHeight)
                .overlay { cover(color) }
                .clipped()
            .overlay(alignment: .topLeading) {
                Text(Formats.relativeDay(start, today: today))
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background {
                        if isToday { Capsule().fill(Palette.brand) } else { Capsule().fill(Color(hex: 0x0F172A, opacity: 0.5)) }
                    }
                    .background(.ultraThinMaterial, in: Capsule())
                    .overlay(Capsule().strokeBorder(.white.opacity(isToday ? 0.45 : 0.3), lineWidth: 1))
                    .padding(8)
            }
            .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 5) {
                    Image(systemName: event.isMultiDay ? "calendar" : "clock").font(.system(size: 11, weight: .bold))
                    Text(event.isMultiDay ? Formats.span(event.date, event.endDate) : (event.startTime.isEmpty ? String(localized: "Ganztägig") : event.startTime))
                        .lineLimit(1)
                }
                .font(.system(size: 12.5, weight: .bold))
                .foregroundStyle(color)
                Text(event.title)
                    .font(.system(size: 16, weight: .heavy))
                    .foregroundStyle(Palette.text)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                if !event.location.isEmpty {
                    HStack(spacing: 5) {
                        Image(systemName: "mappin.and.ellipse").font(.system(size: 11))
                        Text(event.location).lineLimit(1)
                    }
                    .font(.system(size: 12.5))
                    .foregroundStyle(Palette.textSecondary)
                }
                Spacer(minLength: 0)
                chip.padding(.top, 2)
            }
            .padding(.horizontal, 8)
            .padding(.top, 10)
            .padding(.bottom, 6)
            // Grows to the height of the tallest card in the row (UpcomingRow), the chip stays at the bottom
            .frame(maxWidth: .infinity, minHeight: 112, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(6)
        .frame(width: width)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Palette.borderLight, lineWidth: 1))
        .shadow(color: Color(hex: 0x0F172A, opacity: 0.1), radius: 10, y: 6)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func cover(_ color: Color) -> some View {
        let mesh = ZStack {
            ColorMesh(spots: [(point: UnitPoint(x: 0.2, y: 0.25), color: color.opacity(0.35)),
                              (point: UnitPoint(x: 0.85, y: 0.35), color: Color(hex: 0x6366F1, opacity: 0.22)),
                              (point: UnitPoint(x: 0.5, y: 1), color: Color(hex: 0x10B981, opacity: 0.22))])
            Image(systemName: event.isTermin ? "clock" : "calendar")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(color)
        }
        if let url = store.api.absolute(event.imageUrl) {
            RemoteImage(url: url) { mesh }
        } else {
            mesh
        }
    }

    @ViewBuilder
    private var chip: some View {
        if let user = store.user, let duty = event.myConfirmedDuty(user) ?? event.myGroupDuty(user) {
            StatusPill(text: duty.role, color: Palette.indigo, systemImage: "person.fill")
        } else if event.isRegistered {
            StatusPill(text: String(localized: "Angemeldet"), color: Palette.success, systemImage: "checkmark")
        } else if event.isWaitlisted {
            StatusPill(text: String(localized: "Warteliste"), color: Palette.amberText, systemImage: "hourglass")
        } else if event.requiresRegistration && !event.isFull {
            StatusPill(text: String(localized: "Anmeldung offen"), color: Palette.primary)
        }
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
