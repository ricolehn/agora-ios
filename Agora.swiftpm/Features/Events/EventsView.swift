import SwiftUI

/// "Termine & Events": appointments day by day, events as cover cards.
struct EventsView: View {
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router
    @State private var tab: Tab = .termine
    @State private var query = ""
    @State private var showPast = false

    enum Tab: Hashable { case termine, events }

    private var canCreate: Bool {
        guard let user = store.user else { return false }
        return store.data.eventSettings.allowMemberCreation || user.managesEvents || user.isAdmin
    }

    private var isManager: Bool { store.user.map { $0.managesEvents || $0.isAdmin } ?? false }

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
                ForEach(EventRules.byMonth(days, day: { $0.day }), id: \.month) { group in
                    SectionHeader(title: Formats.monthYear(group.month), count: group.items.count)
                    ForEach(group.items) { entry in
                        Button { router.open(.event(entry.event.id)) } label: {
                            EventRow(event: entry.event, day: entry.day, showRegistered: false)
                        }
                        .buttonStyle(.pressable)
                    }
                }
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
            ForEach(highlights) { cover($0) }
        }
        ForEach(EventRules.byMonth(upcoming.filter { !$0.isPinned }, day: { $0.date }), id: \.month) { group in
            SectionHeader(title: Formats.monthYear(group.month), count: group.items.count)
            ForEach(group.items) { cover($0) }
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
            if showPast { ForEach(past) { cover($0) } }
        }
    }

    private func cover(_ event: AgoraEvent) -> some View {
        Button { router.open(.event(event.id)) } label: { EventCoverCard(event: event) }
            .buttonStyle(.pressable)
    }
}
