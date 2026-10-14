import Foundation

// Models of the Extras apps and the order of service (web v3.1 ORION); same tolerant decoding as Models.swift.

// MARK: - Songbook

/// A song of the songbook (server: backend/songbook.js). Capo and tempo are no longer shown or edited, but kept
/// when a song is saved again (like the web app).
struct Song: Codable, Hashable, Identifiable, Sendable {
    var id = ""
    var title = ""
    var artist = ""
    var key = ""
    var capo: Int?
    var tempo: Int?
    var ccli = ""
    var copyright = ""
    var content = ""
    var createdAt: Int64 = 0
    var updatedAt: Int64 = 0

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        id = c.string("id")
        title = c.string("title")
        artist = c.string("artist")
        key = c.string("key")
        capo = c.raw("capo") == nil ? nil : c.int("capo")
        tempo = c.raw("tempo") == nil ? nil : c.int("tempo")
        ccli = c.string("ccli")
        copyright = c.string("copyright")
        content = c.string("content")
        createdAt = c.int64("createdAt")
        updatedAt = c.int64("updatedAt")
    }
}

/// `GET /api/songs`: every song, the church's CCLI licence number and whether the member may edit.
struct Songbook: Decodable, Sendable {
    var songs: [Song] = []
    var ccliLicense = ""
    var canManage = false

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        songs = c.models("songs")
        ccliLicense = c.string("ccliLicense")
        canManage = c.bool("canManage")
    }
}

/// What the song editor sends; capo and tempo come from the edited song (nil for a new one).
struct SongInput: Sendable {
    var title = ""
    var artist = ""
    var key = ""
    var ccli = ""
    var copyright = ""
    var content = ""
    var capo: Int?
    var tempo: Int?
}

// MARK: - Prayer requests

struct PrayerAuthor: Codable, Hashable, Sendable {
    var uid = ""
    var name = ""

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        uid = c.string("uid")
        name = c.string("name")
    }
}

/// A prayer request (server: backend/prayers.js). The server never says who shared an anonymous request;
/// `isMine` and `canDelete` come from it.
struct Prayer: Codable, Hashable, Identifiable, Sendable {
    var id = ""
    var text = ""
    var anonymous = false
    var author: PrayerAuthor?
    var createdAt: Int64 = 0
    var expiresAt: Int64 = 0
    var expired = false
    var isMine = false
    var canDelete = false

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        id = c.string("id")
        text = c.string("text")
        anonymous = c.bool("anonymous")
        author = c.model("author")
        createdAt = c.int64("createdAt")
        expiresAt = c.int64("expiresAt")
        expired = c.bool("expired")
        isMine = c.bool("isMine")
        canDelete = c.bool("canDelete")
    }
}

struct PrayerList: Decodable, Sendable {
    var prayers: [Prayer] = []
    var canModerate = false

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        prayers = c.models("prayers")
        canModerate = c.bool("canModerate")
    }
}

/// How long a request is shown: the server's DURATIONS keys.
enum PrayerDuration: String, CaseIterable, Identifiable, Sendable {
    case week, month, quarter

    var id: String { rawValue }

    var label: String {
        switch self {
        case .week: return String(localized: "1 Woche")
        case .month: return String(localized: "1 Monat")
        case .quarter: return String(localized: "3 Monate")
        }
    }
}

// MARK: - Order of service ("Ablauf")

/// One point of an event's order of service (web v3.1, backend/program.js): items in their order, each with an
/// optional duration. Seen by those who see the duty roster, edited by those who may edit the event.
struct ProgramItem: Codable, Hashable, Identifiable, Sendable {
    var id = ""
    var title = ""
    var minutes: Int?
    var who = ""
    var note = ""
    var songId = ""
    var songKey = ""

    init(id: String = "", title: String = "", minutes: Int? = nil, who: String = "", note: String = "", songId: String = "", songKey: String = "") {
        self.id = id
        self.title = title
        self.minutes = minutes
        self.who = who
        self.note = note
        self.songId = songId
        self.songKey = songKey
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        id = c.string("id")
        title = c.string("title")
        minutes = c.raw("minutes") == nil ? nil : c.int("minutes")
        who = c.string("who")
        note = c.string("note")
        songId = c.string("songId")
        songKey = c.string("songKey")
    }
}

struct Program: Decodable, Sendable {
    var items: [ProgramItem] = []
    var canEdit = false

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        items = c.models("items")
        canEdit = c.bool("canEdit")
    }
}

/// The few song fields the plan needs (song picker, key chip); the songbook has its own full model.
struct PlanSong: Decodable, Hashable, Identifiable, Sendable {
    var id = ""
    var title = ""
    var artist = ""
    var key = ""

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        id = c.string("id")
        title = c.string("title")
        artist = c.string("artist")
        key = c.string("key")
    }
}

struct PlanSongs: Decodable, Sendable {
    var songs: [PlanSong] = []

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        songs = c.models("songs")
    }
}
