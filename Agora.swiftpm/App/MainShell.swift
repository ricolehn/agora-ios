import SwiftUI

/// Tabs like the web app's bottom navigation: Start, Finanzen, Events, Mentoring and (if enabled) KI-Support.
struct MainShell: View {
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router

    private var showsAi: Bool { (store.user?.accessesAi ?? false) && store.data.aiEnabled }

    var body: some View {
        TabView(selection: Binding(get: { router.tab }, set: { router.select($0) })) {
            stack(.home) { HomeView() }
                .tabItem { Label("Start", systemImage: "house") }
                .tag(AppTab.home)

            stack(.finances) { FinancesView() }
                .tabItem { Label("Finanzen", systemImage: "eurosign.circle") }
                .tag(AppTab.finances)

            stack(.events) { EventsView() }
                .tabItem { Label("Events", systemImage: "calendar") }
                .badge(store.data.dutyRequests.count)
                .tag(AppTab.events)

            stack(.mentoring) { MentoringView() }
                .tabItem { Label("Mentoring", systemImage: "person.2") }
                .badge(store.data.unreadThreads.count)
                .tag(AppTab.mentoring)

            if showsAi {
                stack(.ai) { AiChatView() }
                    .tabItem { Label("KI-Support", systemImage: "bubble.left.and.text.bubble.right") }
                    .tag(AppTab.ai)
            }
        }
        // Active tab in emerald like the web app; the content keeps the cyan accent
        .tint(Palette.secondary)
        .onChange(of: showsAi) { _, visible in
            if !visible && router.tab == .ai { router.select(.home) }
        }
    }

    private func stack<Content: View>(_ tab: AppTab, @ViewBuilder content: () -> Content) -> some View {
        NavigationStack(path: router.path(tab)) {
            content()
                .agoraDestinations()
        }
        .tint(Palette.primary)
    }
}

/// Root page of a tab: scrolls with the web app's header (logo, app name, profile menu) on top.
struct TabPage<Content: View>: View {
    @Environment(AppStore.self) private var store
    var spacing: CGFloat = 16
    /// Pull-to-refresh; nil reloads the member data.
    var refresh: (@MainActor () async -> Void)?
    @ViewBuilder var content: Content

    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        // iPad: the whole width with a margin that grows with the screen (like the web); iPhone: 20pt margins
        GeometryReader { proxy in
            let regular = sizeClass == .regular
            let gutter = PageLayout.gutter(width: proxy.size.width, regular: regular)
            ScrollViewReader { scroller in
                ScrollView {
                    VStack(alignment: .leading, spacing: spacing) {
                        TabHeader()
                        content
                    }
                    .padding(.horizontal, gutter)
                    .padding(.bottom, 32)
                    .frame(maxWidth: regular ? .infinity : 800)
                    .frame(maxWidth: .infinity)
                }
                .environment(\.pageScroll, scroller)
            }
            .environment(\.pageGutter, gutter)
            .environment(\.pageContentWidth, max(0, min(proxy.size.width, regular ? .infinity : 800) - gutter * 2))
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Palette.background.ignoresSafeArea())
        .refreshable {
            if let refresh { await refresh() } else { await store.refreshAll(showIndicator: true) }
        }
        .overlay(alignment: .top) { StatusBarScrim() }
        .toolbar(.hidden, for: .navigationBar)
    }
}

/// Fade behind the status bar so the clock stays readable over scrolled content.
struct StatusBarScrim: View {
    var body: some View {
        GeometryReader { proxy in
            LinearGradient(colors: [Palette.background.opacity(0.95), Palette.background.opacity(0.75), Palette.background.opacity(0)],
                           startPoint: .top, endPoint: .bottom)
                .frame(height: proxy.safeAreaInsets.top + 10)
                .ignoresSafeArea(edges: .top)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Logo, gradient app name, offline hint and the profile menu.
struct TabHeader: View {
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router
    @Environment(\.openURL) private var openURL
    @State private var confirmLogout = false

    var body: some View {
        HStack(spacing: 12) {
            ServerLogo(size: 38)
            GradientText(text: store.appName, size: 28)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            if store.data.error != nil {
                Image(systemName: "icloud.slash")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Palette.danger)
                    .accessibilityLabel("Keine Verbindung zum Server")
            }
            if let user = store.user {
                Menu {
                    Section(user.fullName) {
                        Button { router.open(.settings) } label: { Label("Einstellungen", systemImage: "gearshape") }
                        if user.isAdmin, let url = URL(string: store.baseURL + "/#super-admin-settings") {
                            Button { openURL(url) } label: { Label("Systemeinstellungen", systemImage: "shield") }
                        }
                    }
                    Button(role: .destructive) { confirmLogout = true } label: {
                        Label("Abmelden", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                } label: {
                    // Room for the ring's glow: the menu clips its label to the label frame while it animates
                    Avatar(userId: user.userId, name: user.fullName, size: 36, ring: user.ring)
                        .padding(10)
                        .contentShape(Circle())
                }
                .padding(-10)
                .accessibilityLabel("Profilmenü")
            }
        }
        .padding(.top, 10)
        .padding(.bottom, 2)
        .confirmationDialog("Abmelden?", isPresented: $confirmLogout, titleVisibility: .visible) {
            Button("Abmelden", role: .destructive) { Task { await store.logout() } }
        }
    }
}

/// Floating "+" of the web app (events, treasurer finances), above the tab bar.
struct FloatingAddButton<MenuContent: View>: View {
    var accessibility: LocalizedStringKey = "Erstellen"
    @ViewBuilder var menu: MenuContent

    var body: some View {
        Menu {
            menu
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 54, height: 54)
                .background(Palette.brand, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .shadow(color: .black.opacity(0.25), radius: 10, y: 5)
        }
        .accessibilityLabel(accessibility)
        .padding(.trailing, 18)
        .padding(.bottom, 16)
    }
}
