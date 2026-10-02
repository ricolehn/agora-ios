import SwiftUI

enum AppTab: String, Hashable, CaseIterable {
    case home, finances, events, mentoring, ai
}

/// Pages pushed on a tab's navigation stack.
enum Route: Hashable {
    case event(String)
    case eventEdit(id: String?, type: String)
    case chat(String)
    case settings
}

/// Selected tab and one navigation stack per tab, so cards anywhere can open pages or switch tabs.
@MainActor
@Observable
final class Router {
    var tab: AppTab = .home
    var paths: [AppTab: [Route]] = [:]

    func path(_ tab: AppTab) -> Binding<[Route]> {
        Binding(get: { self.paths[tab] ?? [] }, set: { self.paths[tab] = $0 })
    }

    /// Opens a page on the current tab.
    func open(_ route: Route) {
        paths[tab, default: []].append(route)
    }

    /// Switches tab; tapping the current tab again goes back to its root.
    func select(_ newTab: AppTab) {
        if newTab == tab { paths[newTab] = [] }
        tab = newTab
    }

    func back() {
        if !(paths[tab] ?? []).isEmpty { paths[tab]?.removeLast() }
    }

    func reset() {
        tab = .home
        paths = [:]
    }
}

extension View {
    /// The pages every tab can push.
    func agoraDestinations() -> some View {
        navigationDestination(for: Route.self) { route in
            switch route {
            case .event(let id): EventDetailView(eventId: id)
            case .eventEdit(let id, let type): EventEditView(eventId: id, initialType: type)
            case .chat(let id): ChatView(threadId: id)
            case .settings: SettingsView()
            }
        }
    }
}
