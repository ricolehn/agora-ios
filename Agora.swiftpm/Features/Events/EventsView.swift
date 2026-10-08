import SwiftUI

/// "Termine & Events": appointments day by day, events as cover cards.
struct EventsView: View {
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router
    @State private var tab: Tab = .termine
    @State private var query = ""
    @State private var showPast = false

    enum Tab: Hashable { case termine, events }

    // Admins too need the event permission (like the server since v3.0.0)
    private var canCreate: Bool {
        guard let user = store.user else { return false }
        return store.data.eventSettings.allowMemberCreation || user.managesEvents
    }

    private var isManager: Bool { store.user?.managesEvents ?? false }

    var body: some View {
        TabPage {
            PageTitle("Termine & Events")
            PillTabs(items: [
                .init(value: Tab.termine, title: "Termine", systemImage: "calendar"),
                .init(value: Tab.events, title: "Events", systemImage: "sparkles")
            ], selection: $tab)
            SearchField(placeholder: "Termine & Events durchsuchen…", text: $query)
            if !store.data.dutyRequests.isEmpty { DutyRequestCard() }
            if !store.data.loaded && store.data.events.isEmpty {
                LoadingCard()
            } else if tab == .termine {
                termine
            } else {
                events
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if canCreate {
                FloatingAddButton {
                    if isManager {
                        Button { router.open(.eventEdit(id: nil, type: "termin")) } label: { Label("Neuer Termin", systemImage: "calendar.badge.plus") }
                    }
                    Button { router.open(.eventEdit(id: nil, type: "event")) } label: { Label("Neues Event", systemImage: "sparkles") }
                }
            }
        }
        .onAppear(perform: showTermineIfRequested)
        .onChange(of: router.termineRequested) { _, _ in showTermineIfRequested() }
    }

    private func showTermineIfRequested() {
        guard router.termineRequested else { return }
        router.termineRequested = false
        tab = .termine
    }

    private var searched: [AgoraEvent] { store.data.events.filter { EventRules.matches($0, query: query) } }

    @ViewBuilder
    private var termine: some View {
        if let user = store.user {
            let today = Day.today()
            let days = EventRules.days(of: searched.filter { EventRules.showsInTermine($0, user: user, today: today) }, today: today)
            if days.isEmpty {
                EmptyState(systemImage: "calendar", title: "Keine passenden Termine gefunden").card(padding: 0)
            } else {
                TermineSection(days: days, today: today)
            }
        }
    }

    @ViewBuilder
    private var events: some View {
        let today = Day.today()
        let all = searched.filter(EventRules.showsInEvents)
        let upcoming = all.filter { !$0.isPast(today: today) }.sorted(by: EventRules.chronological)
        let past = all.filter { $0.isPast(today: today) }.sorted { $0.date > $1.date }
        let highlights = upcoming.filter(\.isPinned)
        if upcoming.isEmpty {
            EmptyState(systemImage: "sparkles", title: "Keine anstehenden Events gefunden").card(padding: 0)
        }
        if !highlights.isEmpty {
            SectionHeader(title: String(localized: "Highlights"), count: highlights.count, color: Palette.indigo)
            AdaptiveGrid(minWidth: 320, spacing: 16) { ForEach(highlights) { cover($0) } }
        }
        ForEach(EventRules.byMonth(upcoming.filter { !$0.isPinned }, day: { $0.date }), id: \.month) { group in
            SectionHeader(title: Formats.monthYear(group.month), count: group.items.count)
            AdaptiveGrid(minWidth: 320, spacing: 16) { ForEach(group.items) { cover($0) } }
        }
        if !past.isEmpty {
            let toggleTitle = showPast ? String(localized: "Abgelaufene Events ausblenden (\(past.count))")
                : String(localized: "Abgelaufene Events anzeigen (\(past.count))")
            Button {
                withAnimation(.snappy) { showPast.toggle() }
            } label: {
                Label(toggleTitle, systemImage: showPast ? "chevron.up" : "chevron.down")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Palette.textSecondary)
                    .padding(.vertical, 10)
                    .padding(.horizontal, 16)
                    .background(Palette.surface, in: Capsule())
                    .overlay(Capsule().strokeBorder(Palette.border, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 6)
            if showPast { AdaptiveGrid(minWidth: 320, spacing: 16) { ForEach(past) { cover($0) } } }
        }
    }

    private func cover(_ event: AgoraEvent) -> some View {
        Button { router.open(.event(event.id)) } label: { EventCoverCard(event: event) }
            .buttonStyle(.pressable)
    }
}

/// Termine: one card below the other, grouped by month (like the web and Android). On wide iPads a month calendar
/// sits on the left third and stays at the top while the list scrolls; a tap on a day scrolls the list there and
/// lets the cards of that day light up briefly. Lives inside TabPage (page width and scrolling come from there).
struct TermineSection: View {
    @Environment(Router.self) private var router
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.pageContentWidth) private var contentWidth
    @Environment(\.pageScroll) private var pageScroll
    let days: [EventDay]
    let today: String
    @State private var month = Day.month(Day.today())
    @State private var selectedDay: String?
    @State private var glowDay: String?
    @State private var listHeight: CGFloat = 0
    @State private var calendarHeight: CGFloat = 0

    var body: some View {
        let showCalendar = sizeClass == .regular && contentWidth >= 900
        if showCalendar {
            let gap: CGFloat = 28
            let calendarWidth = max(280, (contentWidth - gap) / 3)
            HStack(alignment: .top, spacing: gap) {
                // Room to slide: the calendar stops at the end of the list
                let travel = max(0, listHeight - calendarHeight)
                TermineCalendar(month: $month, days: categories, selected: selectedDay, today: today, onDay: jump)
                    .frame(width: calendarWidth)
                    .background(GeometryReader { proxy in
                        Color.clear.onAppear { calendarHeight = proxy.size.height }
                            .onChange(of: proxy.size.height) { _, height in calendarHeight = height }
                    })
                    // Stays at the top of the page while the list scrolls under it
                    .visualEffect { content, proxy in
                        content.offset(y: min(travel, max(0, -proxy.frame(in: .scrollView).minY + 12)))
                    }
                    .zIndex(1)
                list
                    .background(GeometryReader { proxy in
                        Color.clear.onAppear { listHeight = proxy.size.height }
                            .onChange(of: proxy.size.height) { _, height in listHeight = height }
                    })
            }
        } else {
            list
        }
    }

    private var list: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(EventRules.byMonth(days, day: { $0.day }), id: \.month) { group in
                SectionHeader(title: Formats.monthYear(group.month), count: group.items.count)
                ForEach(group.items) { entry in
                    Button { router.open(.event(entry.event.id)) } label: {
                        EventRow(event: entry.event, day: entry.day, showRegistered: false)
                    }
                    .buttonStyle(.pressable)
                    .overlay {
                        RoundedRectangle(cornerRadius: Radius.list, style: .continuous)
                            .strokeBorder(Palette.primary.opacity(glowDay == entry.day ? 0.45 : 0), lineWidth: 3)
                            .allowsHitTesting(false)
                    }
                    .id(entry.id)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Categories (dots) per day.
    private var categories: [String: Set<TerminCategory>] {
        Dictionary(grouping: days, by: \.day).mapValues { Set($0.map(\.event.terminCategory)) }
    }

    /// Scrolls to the chosen day, or to the next day with entries.
    private func jump(_ day: String) {
        selectedDay = day
        guard let target = days.first(where: { $0.day >= day }) else { return }
        withAnimation(.snappy) { pageScroll?.scrollTo(target.id, anchor: .top) }
        glowDay = target.day
        Task {
            try? await Task.sleep(nanoseconds: 500_000_000)
            withAnimation(.easeOut(duration: 1.1)) { if glowDay == target.day { glowDay = nil } }
        }
    }
}
