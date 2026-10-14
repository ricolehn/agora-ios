import Foundation

/// Server calls of the Extras apps (songbook, prayer requests) and of the event plan (order of service);
/// mirrors SongbookApi.kt, PrayersApi.kt and ProgramApi.kt of the Android app.
extension Repository {
    /// An id as one path segment (never a "/" or "?" of its own).
    private func segment(_ id: String) -> String {
        id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed.subtracting(CharacterSet(charactersIn: "/?#"))) ?? id
    }

    // MARK: Songbook

    func songbook() async throws -> Songbook { try await api.get("/api/songs") }

    /// Creates a song (`id` nil) or saves an existing one; returns the song as stored.
    func saveSong(id: String?, _ input: SongInput) async throws -> Song {
        let body: JSONValue = [
            "title": .string(input.title.trimmingCharacters(in: .whitespaces)),
            "artist": .string(input.artist.trimmingCharacters(in: .whitespaces)),
            "key": .string(input.key.trimmingCharacters(in: .whitespaces)),
            "ccli": .string(input.ccli.trimmingCharacters(in: .whitespaces)),
            "copyright": .string(input.copyright.trimmingCharacters(in: .whitespaces)),
            "content": .string(input.content),
            "capo": input.capo.map { JSONValue.number(Double($0)) } ?? JSONValue.null,
            "tempo": input.tempo.map { JSONValue.number(Double($0)) } ?? JSONValue.null
        ]
        if let id {
            return try await api.send(.put, "/api/songs/\(segment(id))", body: body)
        }
        return try await api.send(.post, "/api/songs", body: body)
    }

    func deleteSong(id: String) async throws {
        try await api.perform(.delete, "/api/songs/\(segment(id))")
    }

    // MARK: Prayer requests

    /// The running requests (newest first) plus the own expired ones.
    func prayers() async throws -> PrayerList { try await api.get("/api/prayers") }

    func sharePrayer(text: String, duration: PrayerDuration, anonymous: Bool) async throws {
        try await api.perform(.post, "/api/prayers", body: [
            "text": .string(text), "duration": .string(duration.rawValue), "anonymous": .bool(anonymous)
        ])
    }

    /// The owner adds a month (from the later of now and the old end).
    func extendPrayer(id: String, duration: PrayerDuration = .month) async throws -> Prayer {
        try await api.send(.patch, "/api/prayers/\(segment(id))", body: ["extend": .string(duration.rawValue)])
    }

    /// Done (owner) or removed by a member with the manage_prayers permission.
    func deletePrayer(id: String) async throws {
        try await api.perform(.delete, "/api/prayers/\(segment(id))")
    }

    // MARK: Order of service

    func program(eventId: String) async throws -> Program { try await api.get("/api/events/\(segment(eventId))/program") }

    func saveProgram(eventId: String, items: [ProgramItem]) async throws -> Program {
        let list: [JSONValue] = items.map { item in
            var entry: JSONValue = [
                "title": .string(item.title), "who": .string(item.who), "note": .string(item.note),
                "songId": .string(item.songId), "songKey": .string(item.songKey)
            ]
            if !item.id.trimmingCharacters(in: .whitespaces).isEmpty { entry["id"] = .string(item.id) }
            if let minutes = item.minutes { entry["minutes"] = .of(minutes) }
            return entry
        }
        return try await api.send(.put, "/api/events/\(segment(eventId))/program", body: ["items": .array(list)])
    }

    func planSongs() async throws -> [PlanSong] { try await api.get("/api/songs", as: PlanSongs.self).songs }

    /// Adds an empty task (no person, no e-mail), like the web's `{ roleName }`.
    func addEmptyTask(eventId: String, roleName: String) async throws {
        try await api.perform(.post, "/api/events/\(segment(eventId))/duties", body: ["roleName": .string(roleName)])
    }
}
