#if DEBUG
import Foundation

/// Debug builds only: puts the app into a given state from launch environment variables, for the simulator
/// screenshots of the CI (`scripts/screenshots`, workflow *Screenshots (iOS)*). `simctl launch` passes variables to
/// the app with the prefix `SIMCTL_CHILD_`. Without `AGORA_SHOT_STAGE` it does nothing.
///
/// - `AGORA_SHOT_STAGE`: `server` (first start), `login` (login of `AGORA_SHOT_SERVER`) or `app` (signed in)
/// - `AGORA_SHOT_SERVER`, `AGORA_SHOT_EMAIL`, `AGORA_SHOT_PASSWORD`: the test server and the account to sign in with;
///   another signed-in account is signed out first
/// - `AGORA_SHOT_TAB`: `home`, `finances`, `events`, `mentoring` or `extras`
/// - `AGORA_SHOT_ROUTE`: `settings`, `ai`, `songbook`, `prayers`, `termine`, `event:<title>`, `chat` (the first
///   conversation) or `new-event`
/// - `AGORA_SHOT_PILL`: index of the in-page tab (`PillTabs`) to show
@MainActor
enum ScreenshotDriver {
    nonisolated private static let env = ProcessInfo.processInfo.environment

    nonisolated static let pill: Int? = env["AGORA_SHOT_PILL"].flatMap(Int.init)

    static func run(store: AppStore, router: Router) async {
        guard let stage = env["AGORA_SHOT_STAGE"] else { return }
        do {
            switch stage {
            case "server":
                if store.user != nil { await store.logout(remote: false) }
                store.changeServer()
            case "login":
                if store.user != nil { await store.logout(remote: false) }
                if let server = env["AGORA_SHOT_SERVER"] { try await store.connect(server) }
            default:
                try await signIn(store)
                await waitForData(store)
                open(store: store, router: router)
            }
            log("AGORA_SHOT ready")
        } catch {
            log("AGORA_SHOT failed: \(APIError.text(error))")
        }
    }

    /// Unbuffered, so the script sees the line while the app runs (stdout to a file is buffered).
    private static func log(_ line: String) {
        FileHandle.standardOutput.write(Data((line + "\n").utf8))
    }

    private static func signIn(_ store: AppStore) async throws {
        guard let server = env["AGORA_SHOT_SERVER"], let email = env["AGORA_SHOT_EMAIL"], let password = env["AGORA_SHOT_PASSWORD"] else { return }
        if let user = store.user, user.email.lowercased() == email.lowercased(), store.baseURL == server { return }
        if store.user != nil { await store.logout(remote: false) }
        try await store.connect(server)
        try await store.login(email: email, password: password)
    }

    /// Until the member data is loaded (at most 20 s).
    private static func waitForData(_ store: AppStore) async {
        for _ in 0..<80 where !store.data.loaded || store.refreshing {
            try? await Task.sleep(nanoseconds: 250_000_000)
        }
    }

    private static func open(store: AppStore, router: Router) {
        if let tab = env["AGORA_SHOT_TAB"].flatMap(AppTab.init(rawValue:)) { router.select(tab) }
        guard let route = env["AGORA_SHOT_ROUTE"], !route.isEmpty else { return }
        switch route {
        case "settings": router.open(.settings)
        case "ai": router.open(.ai)
        case "songbook": router.open(.songbook)
        case "prayers": router.open(.prayers)
        case "termine": router.openTermine()
        case "new-event": router.open(.eventEdit(id: nil, type: "event"))
        case "chat":
            if let thread = store.data.threads.first { router.open(.chat(thread.id)) }
        default:
            if route.hasPrefix("event:") {
                let title = String(route.dropFirst("event:".count))
                if let event = store.data.events.first(where: { $0.title == title }) { router.open(.event(event.id)) }
            } else {
                log("AGORA_SHOT unknown route \(route)")
            }
        }
    }
}
#endif
