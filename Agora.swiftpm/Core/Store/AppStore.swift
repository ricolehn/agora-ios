import Foundation
import Observation

enum AuthState: Equatable {
    case loading
    case needsServer
    case needsLogin(baseURL: String)
    case loggedIn(User)
}

/// Everything the member-facing screens show; refreshed as a whole on live updates, kept on the device (DataCache).
struct AppData: Codable, Sendable {
    var loaded = false
    var fees = FeeSettings()
    var ownPerson: Person?
    var ownRequests: [FinanceRequest] = []
    /// Open requests of all members; only filled for those who decide on them (treasurers, owner).
    var pendingRequests: [FinanceRequest] = []
    var events: [AgoraEvent] = []
    var dutyRequests: [DutyRequest] = []
    var threads: [MentoringThread] = []
    var mentorProfile = MyMentorProfile()
    var eventSettings = EventSettings()
    var groups: [MemberGroup] = []
    var aiEnabled = false
    var error: String?

    var unreadThreads: [MentoringThread] { threads.filter { $0.unreadCount > 0 } }
    var unreadMessages: Int { threads.reduce(0) { $0 + max(0, $1.unreadCount) } }

    func event(_ id: String) -> AgoraEvent? { events.first { $0.id == id } }
    func thread(_ id: String) -> MentoringThread? { threads.first { $0.id == id } }
    /// Name of a target group: ids are resolved, names (saved by the web editor) stay as they are.
    func groupName(_ id: String) -> String { groups.first { $0.id == id || $0.name == id }?.name ?? id }
}

/// App state: session, member data, live updates. All screens read it; actions go through the repository and
/// then refresh the affected data.
@MainActor
@Observable
final class AppStore {
    private(set) var auth: AuthState = .loading
    private(set) var data = AppData()
    private(set) var refreshing = false
    private(set) var appName = "Agora"
    /// Bumped when the server reported changes; `changedAreas` says which ("all", "events", "mentoring").
    private(set) var changeTick = 0
    private(set) var changedAreas: Set<String> = []

    let repository: Repository
    private let session: SessionStore
    private let cache: DataCache?
    @ObservationIgnored private var liveTask: Task<Void, Never>?
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var refreshQueued = false
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private var restoreStarted = false
    /// Cleans up UI-side caches (pictures) of the signed-out account.
    @ObservationIgnored var onLogout: (@MainActor () -> Void)?

    var api: APIClient { repository.api }
    var user: User? { if case .loggedIn(let user) = auth { return user } else { return nil } }
    var baseURL: String { api.baseURL }

    init(repository: Repository, session: SessionStore, cache: DataCache?) {
        self.repository = repository
        self.session = session
        self.cache = cache
        repository.api.onUnauthorized = { [weak self] in
            Task { @MainActor in
                guard let self, case .loggedIn = self.auth else { return }
                await self.logout(remote: false)
            }
        }
    }

    // MARK: Session

    /// Restores the saved session: opens with the cached user and data, validates both in the background.
    func restore() async {
        guard !restoreStarted else { return }
        restoreStarted = true
        if let name = session.appName { appName = name }
        let saved = session.current()
        guard !saved.baseURL.isEmpty else {
            auth = .needsServer
            return
        }
        api.baseURL = saved.baseURL
        guard let token = saved.token, let user = saved.user else {
            auth = .needsLogin(baseURL: saved.baseURL)
            return
        }
        api.token = token
        if let cached = cache?.load(baseURL: saved.baseURL, userId: user.userId) { data = cached }
        auth = .loggedIn(user)
        // Session check and data refresh side by side
        Task { await refreshAll() }
        Task {
            if let fresh = try? await repository.me() {
                session.updateUser(fresh)
                if case .loggedIn = auth { auth = .loggedIn(fresh) }
            }
        }
    }

    func connect(_ input: String) async throws {
        let url = try Self.normalize(input)
        let status = try await repository.status(baseURL: url)
        if status.setupMode { throw APIError(status: 503, message: "Dieser Server ist noch nicht eingerichtet. Bitte schließe die Einrichtung zuerst im Browser ab.") }
        session.setBaseURL(url)
        if let name = await repository.appName() {
            appName = name
            session.setAppName(name)
        }
        auth = .needsLogin(baseURL: url)
    }

    /// "gemeinde.de/" → "https://gemeinde.de"; plain http only for local test servers.
    static func normalize(_ input: String) throws -> String {
        var url = input.trimmingCharacters(in: .whitespacesAndNewlines).droppingSuffix("/")
        guard !url.isEmpty else { throw APIError(status: 0, message: "Bitte gib die Server-Adresse ein.") }
        if !url.contains("://") { url = "https://" + url }
        guard let components = URLComponents(string: url), let host = components.host, !host.isEmpty else {
            throw APIError(status: 0, message: "Ungültige Server-Adresse")
        }
        if components.scheme == "http", !["localhost", "127.0.0.1"].contains(host) {
            throw APIError(status: 426, message: "Der Server muss über HTTPS erreichbar sein.")
        }
        guard components.scheme == "https" || components.scheme == "http" else { throw APIError(status: 0, message: "Ungültige Server-Adresse") }
        return url
    }

    func changeServer() { auth = .needsServer }

    func login(email: String, password: String) async throws {
        try await completeLogin(token: try await repository.login(email: email, password: password).token)
    }

    func register(code: String, email: String, firstName: String, lastName: String, password: String) async throws {
        try await completeLogin(token: try await repository.register(code: code, email: email, firstName: firstName, lastName: lastName, password: password).token)
    }

    private func completeLogin(token: String?) async throws {
        guard let token, !token.isEmpty else { throw APIError(status: 500, message: "Keine Sitzung erhalten") }
        api.token = token
        let user = try await repository.me()
        session.setSession(token: token, user: user)
        if let name = await repository.appName() {
            appName = name
            session.setAppName(name)
        }
        data = AppData()
        auth = .loggedIn(user)
        Task { await refreshAll() }
    }

    func logout(remote: Bool = true) async {
        stopLiveUpdates()
        if remote { await repository.logout() }
        api.token = nil
        api.clearHTTPCache()
        onLogout?()
        session.clearSession()
        cache?.clear()
        data = AppData()
        auth = .needsLogin(baseURL: api.baseURL)
    }

    func reloadUser() async throws {
        let fresh = try await repository.me()
        session.updateUser(fresh)
        auth = .loggedIn(fresh)
    }

    // MARK: Data

    /// Loads all member data in parallel; a failing call keeps its previous value.
    func refreshAll(showIndicator: Bool = false) async {
        if let running = refreshTask {
            await running.value
            return
        }
        let task = Task { await loadAll(showIndicator: showIndicator) }
        refreshTask = task
        await task.value
        refreshTask = nil
    }

    /// Fire-and-forget refresh; calls while one is running are merged into one more run.
    func refreshInBackground() {
        if refreshTask != nil {
            refreshQueued = true
            return
        }
        Task {
            await refreshAll()
            if refreshQueued {
                refreshQueued = false
                await refreshAll()
            }
        }
    }

    private func loadAll(showIndicator: Bool) async {
        guard let user else { return }
        if showIndicator { refreshing = true }
        defer { refreshing = false }
        let repo = repository
        let old = data
        let uid = user.userId
        let wantsAi = user.accessesAi
        let decides = user.managesFinances || user.owner
        async let fees = try? repo.feeSettings()
        async let person: Result<Person?, Error> = Self.result { try await repo.ownPeople(uid: uid).first }
        // Members only get their own requests from the server; treasurers all of them
        async let requests = try? repo.allRequests()
        async let events: Result<[AgoraEvent], Error> = Self.result { try await repo.events() }
        async let duties = try? repo.myDutyRequests()
        async let threads = try? repo.threads()
        async let mentorProfile = repo.myMentorProfile()
        async let eventSettings = repo.eventSettings()
        async let groups = repo.groups()
        async let ai: Bool = Self.aiEnabled(repo, wanted: wantsAi)

        var next = old
        next.loaded = true
        next.fees = await fees ?? old.fees
        if case .success(let loaded) = await person { next.ownPerson = loaded }
        if let all = await requests {
            // Own: by author or by the own person record (deciding used to overwrite the author with the treasurer)
            let personId = next.ownPerson?.id
            next.ownRequests = all.filter { $0.userId == uid || (personId != nil && $0.personId == personId) }
            next.pendingRequests = decides ? all.filter(\.isPending) : []
        } else if !decides {
            next.pendingRequests = []
        }
        switch await events {
        case .success(let list):
            next.events = list
            next.error = nil
        case .failure(let error):
            next.error = APIError.text(error)
        }
        next.dutyRequests = await duties ?? old.dutyRequests
        next.threads = await threads ?? old.threads
        next.mentorProfile = await mentorProfile
        next.eventSettings = await eventSettings
        let loadedGroups = await groups
        next.groups = loadedGroups.isEmpty ? old.groups : loadedGroups
        next.aiEnabled = await ai
        data = next
        scheduleSave()
    }

    private nonisolated static func result<T>(_ work: () async throws -> T) async -> Result<T, Error> {
        do { return .success(try await work()) } catch { return .failure(error) }
    }

    private nonisolated static func aiEnabled(_ repo: Repository, wanted: Bool) async -> Bool {
        wanted ? await repo.aiEnabled() : false
    }

    /// Only events (and duty requests) again, after a live update or an event action.
    func refreshEvents() async {
        async let events = try? repository.events()
        async let duties = try? repository.myDutyRequests()
        if let list = await events { data.events = list }
        if let list = await duties { data.dutyRequests = list }
        scheduleSave()
    }

    func refreshThreads() async {
        if let list = try? await repository.threads() {
            data.threads = list
            scheduleSave()
        }
    }

    /// Optimistic local change (e.g. an answered duty request disappears at once).
    func update(_ change: (inout AppData) -> Void) {
        change(&data)
        scheduleSave()
    }

    private func scheduleSave() {
        guard let cache, let user else { return }
        saveTask?.cancel()
        let base = api.baseURL
        let userId = user.userId
        saveTask = Task { [data] in
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            guard !Task.isCancelled, data.loaded else { return }
            var snapshot = data
            snapshot.error = nil
            let finished = snapshot
            await Task.detached(priority: .utility) { cache.save(baseURL: base, userId: userId, data: finished) }.value
        }
    }

    // MARK: Live updates

    /// Server-sent change notifications while the app is in the foreground; bursts are merged for 0.6 s.
    func startLiveUpdates() {
        guard liveTask == nil, user != nil else { return }
        let stream = repository.liveUpdates()
        liveTask = Task { [weak self] in
            for await area in stream {
                guard let self else { return }
                self.collect(area)
            }
        }
    }

    @ObservationIgnored private var pendingAreas: Set<String> = []
    @ObservationIgnored private var flushTask: Task<Void, Never>?

    private func collect(_ area: String) {
        pendingAreas.insert(area)
        flushTask?.cancel()
        flushTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 600_000_000)
            guard !Task.isCancelled, let self else { return }
            let areas = self.pendingAreas
            self.pendingAreas.removeAll()
            await self.apply(changes: areas)
        }
    }

    func stopLiveUpdates() {
        liveTask?.cancel()
        liveTask = nil
        flushTask?.cancel()
        pendingAreas.removeAll()
    }

    private func apply(changes areas: Set<String>) async {
        changedAreas = areas
        changeTick += 1
        if areas.isSubset(of: ["events", "mentoring"]) {
            if areas.contains("events") { await refreshEvents() }
            if areas.contains("mentoring") { await refreshThreads() }
        } else {
            await refreshAll()
        }
    }

    /// App back in the foreground.
    func didBecomeActive() {
        startLiveUpdates()
        if data.loaded { refreshInBackground() }
    }

    func didEnterBackground() {
        stopLiveUpdates()
    }
}
