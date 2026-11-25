import Foundation

/// The calendar of API v2 (docs/API_V2.md, "The calendar") in the old API's shapes, so the app's models decode it and the
/// screens show the same whichever API the server answers (Android: V2Calendar.kt).
enum V2Calendar {
    private static func renamed(_ value: JSONValue, _ names: [String: String]) -> [String: JSONValue] {
        var object = value.objectValue ?? [:]
        for (new, old) in names where object[new] != nil {
            object[old] = object[new]
            object[new] = nil
        }
        return object
    }

    /// A duty of the roster; [canEdit]: whoever may edit the event manages its duties and their notes – as the old API
    /// said of every duty.
    static func duty(_ value: JSONValue, canEdit: Bool) -> JSONValue {
        var duty = renamed(value, ["eventId": "event", "assignedGroupId": "assignedGroup", "assignedUserId": "assignedUser",
                                   "requestedUserId": "requestedUser", "requestedById": "requestedBy"])
        duty["canEditNotes"] = .bool(canEdit)
        duty["canManageDuty"] = .bool(canEdit)
        return .object(duty)
    }

    /// An event as the person sees it: `duties` is the roster for those who see it (null for everyone else).
    static func event(_ value: JSONValue) -> JSONValue {
        var event = renamed(value, ["kind": "eventType", "shareToken": "publicToken"])
        let canEdit = event["canEdit"]?.boolValue ?? false
        if let duties = event["duties"]?.arrayValue {
            event["duties"] = .array(duties.map { duty($0, canEdit: canEdit) })
            event["canAccessDutyPlan"] = true
        } else {
            event["duties"] = .array([])
            event["canAccessDutyPlan"] = false
        }
        event["program"] = nil
        return .object(event)
    }

    /// A duty the person was asked to do and has not answered yet.
    static func dutyRequest(_ value: JSONValue) -> JSONValue {
        .object(renamed(value, ["dutyId": "id", "requestedById": "requestedBy"]))
    }

    /// The participants in the order they signed up: who comes, who waits; a guest named `guest:<guestId>` – the name a
    /// removal takes, too.
    static func attendees(_ participants: [JSONValue]) -> JSONValue {
        func attendee(_ value: JSONValue) -> JSONValue {
            var object = value.objectValue ?? [:]
            let guest = object["isGuest"]?.boolValue ?? false
            object["guest"] = .bool(guest)
            if guest { object["userId"] = .string("guest:" + (object["guestId"]?.text ?? "")) }
            return .object(object)
        }
        return [
            "registered": .array(participants.filter { $0["status"]?.text == "registered" }.map(attendee)),
            "waitlist": .array(participants.filter { $0["status"]?.text == "waitlist" }.map(attendee))
        ]
    }

    /// The order of service of an event read whole (`GET /events/:id`), for one who may edit it or not.
    static func program(ofEvent value: JSONValue) -> JSONValue {
        ["items": value["program"]?["items"] ?? .array([]), "canEdit": value["canEdit"] ?? .bool(false)]
    }

    /// The people a duty can go to and the groups.
    static func candidates(people: [JSONValue], groups: [JSONValue]) -> JSONValue {
        ["candidates": .array(people), "groups": .array(groups)]
    }
}
