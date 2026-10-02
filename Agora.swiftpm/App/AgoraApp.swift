import SwiftUI

@main
struct AgoraIOSApp: App {
    @State private var store: AppStore
    @State private var toasts = ToastCenter()
    @State private var router = Router()
    @AppStorage(AppInfo.themeKey) private var theme = ThemeChoice.system.rawValue
    @Environment(\.scenePhase) private var scenePhase

    @MainActor init() {
        let api = APIClient(userAgent: "AgoraiOS/\(AppInfo.version)")
        let store = AppStore(repository: Repository(api: api), session: SessionStore(), cache: DataCache())
        ImagePipeline.shared.api = api
        store.onLogout = { ImagePipeline.shared.clear() }
        _store = State(initialValue: store)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .environment(toasts)
                .environment(router)
                .preferredColorScheme(ThemeChoice(rawValue: theme)?.scheme)
                .tint(Palette.primary)
                .task { await store.restore() }
                .onChange(of: scenePhase) { _, phase in
                    switch phase {
                    case .active: store.didBecomeActive()
                    case .background: store.didEnterBackground()
                    default: break
                    }
                }
        }
    }
}

enum AppInfo {
    static let themeKey = "agora.theme"

    static var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "0.1"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "\(short) (\(build))"
    }
}

/// Server, login or the app, by session state.
struct RootView: View {
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router

    var body: some View {
        ZStack {
            Palette.background.ignoresSafeArea()
            switch store.auth {
            case .loading:
                SplashView()
            case .needsServer:
                ServerView()
                    .transition(.opacity)
            case .needsLogin(let baseURL):
                LoginView(baseURL: baseURL)
                    .transition(.opacity)
            case .loggedIn:
                MainShell()
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: authKey)
        .overlay { ToastOverlay() }
        .onChange(of: authKey) { _, key in
            if key != "app" { router.reset() }
        }
    }

    private var authKey: String {
        switch store.auth {
        case .loading: return "loading"
        case .needsServer: return "server"
        case .needsLogin: return "login"
        case .loggedIn: return "app"
        }
    }
}

struct SplashView: View {
    var body: some View {
        VStack(spacing: 18) {
            AppMark(size: 64)
            ProgressView().tint(Palette.primary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
