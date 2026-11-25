import Foundation

/// The server answers no API v2 (any more): what was asked is done through the old API instead.
struct V2Unavailable: Error {}

/// API v2 of the server (`/api/v2`, CALDERA; docs/API_V2.md in the agora repository), like Android's `ApiV2`: record
/// ids, money in whole cents, days as `YYYY-MM-DD`, every list in pages with a cursor, every error as
/// `{error: {code, message}}`, and changes that name the version of the data they are based on – refused with 409
/// instead of overwriting what someone else changed meanwhile. Signed in with the same token as the old API.
final class ApiV2: Sendable {
    static let base = "/api/v2"
    /// The largest page v2 hands out.
    static let maxLimit = 500
    /// 500 × 2000 entries: far beyond any community's books; a cursor that does not move on would ask for ever.
    private static let maxPages = 2_000

    /// The resources of the books the app reads and changes through v2. The betas of CALDERA before 3.4.0-beta6 offered
    /// only some of them: they are asked the old way, which they answer as every server does.
    static let books: Set<String> = [
        "members", "payments", "standing-orders", "status-changes", "donations", "expenses", "receipts", "requests",
        "finance/ledger", "finance/summary"
    ]

    /// Every resource the app goes through v2. All or nothing: the app talks to a server through one API, so what it
    /// shows always fits together. Signing in, the live updates and the AI assistant stay with the old API, as v2 says
    /// of itself.
    static let needed: Set<String> = books.union([
        "fees", "fresh-starts",
        "events", "duties", "duty-requests", "people", "calendar-feed",
        "me", "groups", "registration-code", "pictures", "me/picture", "reports",
        "songs", "prayers", "mentoring/mentors", "mentoring/profile", "mentoring/application", "mentoring/threads"
    ])

    let api: APIClient

    init(api: APIClient) { self.api = api }

    /// Whether the server answers v2 (as far as the app knows).
    var available: Bool { api.apiV2 }

    /// Whether the server's v2 offers every resource the app goes through (`GET /api/v2`, signed in).
    func offersAll() async throws -> Bool {
        let index: V2Index = try await api.send(.get, Self.base, reportUnauthorized: false)
        return Self.needed.isSubset(of: Set(index.resources))
    }

    /// [id] as one segment of a path (a guest's `guest:<id>` with its colon encoded).
    static func segment(_ id: String) -> String {
        id.addingPercentEncoding(withAllowedCharacters: .alphanumerics.union(CharacterSet(charactersIn: "-._~"))) ?? id
    }

    /// The address of [path] of v2 (receipts, pictures: loaded as files).
    func absolute(_ path: String) -> URL? { api.absolute(Self.base + path) }

    /// A route of v2 the server does not know (404 without v2's error shape – v2 itself answers every unknown path with
    /// `not_found`): it has no v2 (any more). Nothing was done then, so the caller can do it the old way.
    private func unavailable(_ error: Error) -> Bool {
        guard let api = error as? APIError, api.status == 404, api.code == nil else { return false }
        self.api.apiV2 = false
        return true
    }

    /// One call of v2; throws `V2Unavailable` when the server answers no v2 – known before, or found out now.
    func call<T: Decodable>(_ method: HTTPMethod, _ path: String, query: [String: String] = [:], body: JSONValue? = nil,
                            as type: T.Type = T.self) async throws -> T {
        guard api.apiV2 else { throw V2Unavailable() }
        do {
            return try await api.send(method, Self.base + path, query: query, body: body, as: type)
        } catch {
            if unavailable(error) { throw V2Unavailable() }
            throw error
        }
    }

    /// A call whose answer does not matter.
    func perform(_ method: HTTPMethod, _ path: String, query: [String: String] = [:], body: JSONValue? = nil) async throws {
        _ = try await call(method, path, query: query, body: body, as: JSONValue.self)
    }

    /// A file sent to v2 (multipart); as `call`, a server without v2 is found out.
    func upload<T: Decodable>(_ path: String, file: APIClient.FilePart, as type: T.Type = T.self) async throws -> T {
        guard api.apiV2 else { throw V2Unavailable() }
        do {
            return try await api.upload(Self.base + path, file: file, as: type)
        } catch {
            if unavailable(error) { throw V2Unavailable() }
            throw error
        }
    }

    /// One page of the list at [path]: the first one, or the one after [cursor].
    func page<T: Decodable>(_ path: String, of type: T.Type, query: [String: String] = [:], cursor: String? = nil,
                            limit: Int = maxLimit) async throws -> V2Page<T> {
        var asked = query
        asked["limit"] = String(limit)
        if let cursor { asked["cursor"] = cursor }
        return try await call(.get, path, query: asked, as: V2Page<T>.self)
    }

    /// The whole list at [path], page after page; with the version of the list as the last page names it.
    func all<T: Decodable>(_ path: String, of type: T.Type, query: [String: String] = [:]) async throws -> V2Page<T> {
        var items: [T] = []
        var cursor: String?
        var version: String?
        var pages = 0
        repeat {
            let page = try await page(path, of: type, query: query, cursor: cursor)
            items += page.items
            version = page.listVersion
            cursor = page.nextCursor
            pages += 1
            if pages > Self.maxPages { throw APIError(status: 0, message: "Too many pages") }
        } while cursor != nil
        return V2Page(items: items, listVersion: version)
    }

    /// The whole list at [path] and its first page as it came: for a list that says more than its items (the songbook
    /// its licence number, the prayer requests whether the reader moderates them).
    func collect<T: Decodable>(_ path: String, of type: T.Type, query: [String: String] = [:]) async throws -> (items: [T], first: JSONValue) {
        var items: [T] = []
        var first: JSONValue?
        var cursor: String?
        var pages = 0
        repeat {
            var asked = query
            asked["limit"] = String(Self.maxLimit)
            if let cursor { asked["cursor"] = cursor }
            let page: JSONValue = try await call(.get, path, query: asked)
            if first == nil { first = page }
            for item in page["items"]?.arrayValue ?? [] {
                if let decoded = try? JSONDecoder().decode(T.self, from: JSONEncoder().encode(item)) { items.append(decoded) }
            }
            cursor = page["nextCursor"]?.text.flatMap { $0.isEmpty ? nil : $0 }
            pages += 1
            if pages > Self.maxPages { throw APIError(status: 0, message: "Too many pages") }
        } while cursor != nil
        return (items, first ?? [:])
    }
}
