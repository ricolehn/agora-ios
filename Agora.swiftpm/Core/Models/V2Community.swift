import Foundation

/// The community of API v2 (docs/API_V2.md, "Community") in the old API's shapes, so the app's models decode it:
/// the songbook, prayer requests and mentoring (Android: V2Community.kt). Moments come as ISO 8601.
enum V2Community {
    private static func millis(_ value: JSONValue?) -> JSONValue {
        guard let text = value?.text, let date = Formats.timestamp(text) else { return .number(0) }
        return .number((date.timeIntervalSince1970 * 1000).rounded())
    }

    private static func renamed(_ value: JSONValue, _ names: [String: String]) -> [String: JSONValue] {
        var object = value.objectValue ?? [:]
        for (new, old) in names where object[new] != nil {
            object[old] = object[new]
            object[new] = nil
        }
        return object
    }

    static func song(_ value: JSONValue) -> JSONValue {
        var song = value.objectValue ?? [:]
        song["createdAt"] = millis(value["createdAt"])
        song["updatedAt"] = millis(value["updatedAt"])
        return .object(song)
    }

    /// A prayer request: shared anonymously it names nobody – not even to the leaders.
    static func prayer(_ value: JSONValue) -> JSONValue {
        var prayer = renamed(value, ["isAnonymous": "anonymous", "isExpired": "expired"])
        let uid = value["authorUserId"]?.text
        let name = value["authorName"]?.text
        prayer["author"] = uid == nil && name == nil ? .null : ["uid": .string(uid ?? ""), "name": .string(name ?? "")]
        prayer["createdAt"] = millis(value["createdAt"])
        prayer["expiresAt"] = millis(value["expiresAt"])
        return .object(prayer)
    }

    /// A mentor (those who manage mentoring also see the applications and the e-mail addresses).
    static func mentor(_ value: JSONValue) -> JSONValue { .object(renamed(value, ["userId": "user", "email": "userEmail"])) }

    /// The person's own profile as a mentor (`profile` null: they never applied).
    static func myProfile(_ value: JSONValue) -> JSONValue {
        let profile = value["profile"] ?? .null
        return ["exists": .bool(!profile.isNull), "mentor": profile]
    }

    /// A conversation as the reader sees it: the mentee stays anonymous to the mentor (an alias).
    static func thread(_ value: JSONValue) -> JSONValue {
        var thread = renamed(value, ["mentorUserId": "mentor", "updatedAt": "updated", "role": "myRole",
                                     "isBlocked": "blocked", "isBlockedByMe": "blockedByMe"])
        let text = value["lastMessage"]?.text ?? ""
        let at = value["lastMessageAt"]?.text
        // The last message as the old API named it; none yet: the list shows that it is new
        thread["lastMessage"] = text.trimmingCharacters(in: .whitespaces).isEmpty && at == nil ? .null : ["text": .string(text), "created": .string(at ?? "")]
        return .object(thread)
    }

    /// A message of the conversation [threadId] read by one in the part [myRole]: theirs, or the partner's.
    static func message(_ value: JSONValue, threadId: String, myRole: String) -> JSONValue {
        let from = value["from"]?.text ?? ""
        return [
            "id": value["id"] ?? .string(""), "thread": .string(threadId), "senderRole": .string(from),
            "sender": .string(from == myRole ? "me" : "partner"), "text": value["text"] ?? .string(""),
            "read": value["isRead"] ?? .bool(false), "created": value["createdAt"] ?? .string("")
        ]
    }
}
