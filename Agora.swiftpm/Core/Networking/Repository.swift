import Foundation

/// Event form content sent to POST/PATCH /api/events.
struct EventInput: Sendable {
    var title = ""
    var date = ""
    var endDate = ""
    var startTime = ""
    var endTime = ""
    var location = ""
    var description = ""
    var eventType = "event"
    var isPinned = false
    var requiresRegistration = false
    var minParticipants = 0
    var maxParticipants = 0
    var targetGroups: [String] = []
    var imageUrl = ""
    var isRecurring = false
    var recurringRule = "weekly"
    var recurringCount = 4
    var duties: [String] = []
}

enum AiChunk: Sendable {
    case content(String)
    case reasoning(String)
}

/// All server calls of the app; mirrors the Android `AgoraRepository` so both clients write identical records.
final class Repository: Sendable {
    let api: APIClient

    init(api: APIClient) { self.api = api }

    // MARK: Server & auth

    func status(baseURL: String) async throws -> StatusResponse {
        api.baseURL = baseURL
        return try await api.send(.get, "/api/status", reportUnauthorized: false)
    }

    /// App name from the web app's config module (`appName: "..."`).
    func appName() async -> String? {
        guard let script = try? await api.text("/assets/config.js") else { return nil }
        guard let range = script.range(of: #"appName:\s*"((?:[^"\\]|\\.)*)""#, options: .regularExpression) else { return nil }
        let match = String(script[range])
        guard let start = match.firstIndex(of: "\""), let end = match.lastIndex(of: "\""), start < end else { return nil }
        let quoted = String(match[start...end])
        return (try? JSONDecoder().decode(String.self, from: Data(quoted.utf8))) ?? String(quoted.dropFirst().dropLast())
    }

    func login(email: String, password: String) async throws -> AuthResponse {
        try await api.send(.post, "/api/auth/login",
                           body: ["email": .string(email.trimmingCharacters(in: .whitespaces)), "password": .string(password)],
                           reportUnauthorized: false)
    }

    func register(code: String, email: String, firstName: String, lastName: String, password: String) async throws -> AuthResponse {
        try await api.send(.post, "/api/auth/register", body: [
            "inviteCode": .string(code.trimmingCharacters(in: .whitespaces)),
            "email": .string(email.trimmingCharacters(in: .whitespaces)),
            "firstName": .string(firstName.trimmingCharacters(in: .whitespaces)),
            "lastName": .string(lastName.trimmingCharacters(in: .whitespaces)),
            "password": .string(password)
        ], reportUnauthorized: false)
    }

    func me() async throws -> User {
        let response: AuthResponse = try await api.get("/api/auth/me")
        guard let user = response.user else { throw APIError(status: 401, message: "Unauthorized") }
        return user
    }

    func logout() async {
        try? await api.perform(.post, "/api/auth/logout")
    }

    func changePassword(old: String, new: String) async throws {
        try await api.perform(.post, "/api/auth/password", body: ["oldPassword": .string(old), "password": .string(new)])
    }

    /// Deletes the own account and its personal data (App Store guideline 5.1.1(v)).
    func deleteAccount(password: String) async throws {
        try await api.perform(.post, "/api/auth/delete-account", body: ["password": .string(password)])
    }

    /// Reports an AI reply ("ai") or a conversation ("chat") to the admins.
    func report(type: String, content: String, reason: String, prompt: String = "", threadId: String = "") async throws {
        var body: JSONValue = ["type": .string(type), "content": .string(content), "reason": .string(reason)]
        if !prompt.isEmpty { body["prompt"] = .string(prompt) }
        if !threadId.isEmpty { body["threadId"] = .string(threadId) }
        try await api.perform(.post, "/api/reports", body: body)
    }

    // MARK: Profile & settings

    func uploadProfilePicture(jpeg: Data) async throws {
        let _: JSONValue = try await api.upload("/api/profile/picture",
                                                file: .init(field: "picture", fileName: "profile.jpg", mimeType: "image/jpeg", data: jpeg))
    }

    func profilePictureURL(_ uid: String) -> URL? { uid.isEmpty ? nil : api.absolute("/api/profile/picture/\(uid)") }

    /// Saves channels and kinds like the web (the flat keys repeat the push choice for older servers and apps).
    func saveNotificationSettings(uid: String, _ prefs: NotificationPrefs) async throws {
        var settings = prefs.push.json
        settings["channels"] = ["push": .bool(prefs.channels.push), "email": .bool(prefs.channels.email)]
        settings["push"] = prefs.push.json
        settings["email"] = prefs.email.json
        try await api.perform(.patch, "/api/db", body: [
            "path": .string("users/\(uid)"),
            "value": [
                "notificationSettings": settings,
                "emailNotifications": .bool(prefs.channels.push || prefs.channels.email)
            ]
        ])
    }

    func calendarFeed() async throws -> CalendarFeed { try await api.get("/api/user/calendar-feed") }
    func resetCalendarFeed() async throws -> CalendarFeed { try await api.send(.post, "/api/user/calendar-feed/reset") }

    func inviteCode() async -> String? {
        guard let value: JSONValue = try? await api.get("/api/db", query: ["path": "system/inviteCode"]) else { return nil }
        return value.text
    }

    func setInviteCode(_ code: String) async throws {
        try await api.perform(.put, "/api/db", body: ["path": "system/inviteCode", "value": .string(code)])
    }

    func feeSettings() async throws -> FeeSettings { try await api.get("/api/db", query: ["path": "settings"]) }

    func saveFeeSettings(_ rates: [String: Double]) async throws {
        var current: JSONValue = (try? await api.get("/api/db", query: ["path": "settings"], as: JSONValue.self)) ?? [:]
        if current.objectValue == nil { current = [:] }
        for (key, value) in rates { current[key] = .number(value) }
        try await api.perform(.put, "/api/db", body: ["path": "settings", "value": current])
    }

    func groups() async -> [MemberGroup] { (try? await api.get("/api/groups", as: LossyList<MemberGroup>.self).items) ?? [] }

    // MARK: Finances (member)

    func ownPeople(uid: String) async throws -> [Person] {
        let collection: KeyedCollection<Person> = try await api.get("/api/db", query: ["path": "people", "orderByChild": "uid", "equalTo": uid])
        return collection.items.filter { !$0.isDeleted }
    }

    func allPeople() async throws -> [Person] {
        let collection: KeyedCollection<Person> = try await api.get("/api/db", query: ["path": "people"])
        return collection.items.filter { !$0.isDeleted }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func person(id: String) async throws -> Person? {
        let value: JSONValue = try await api.get("/api/db", query: ["path": "people/\(id)"])
        guard !value.isNull, value.objectValue != nil else { return nil }
        return try? api.decoder.decode(Person.self, from: api.encoder.encode(value))
    }

    /// Members get only their own requests from the server (also decided ones, via their person record).
    func allRequests() async throws -> [FinanceRequest] {
        let collection: KeyedCollection<FinanceRequest> = try await api.get("/api/db", query: ["path": "requests"])
        return collection.items.sorted { $0.timestamp > $1.timestamp }
    }

    /// Uploads a receipt; name and date go first because the server builds the stored file name from them.
    func uploadReceipt(ownerName: String, date: String, fileName: String, mimeType: String, data: Data) async throws -> String {
        let response: UploadResponse = try await api.upload("/api/upload", fields: [("name", ownerName), ("date", date)],
                                                             file: .init(field: "receipt", fileName: fileName, mimeType: mimeType, data: data))
        return response.filename
    }

    /// Receipt names come from request data members write: only a plain file name, encoded, goes into the path.
    func receiptURL(_ fileName: String) -> URL? {
        let name = fileName.split(whereSeparator: { $0 == "/" || $0 == "\\" }).last.map(String.init) ?? ""
        guard !name.isEmpty, name != ".", name != "..",
              let encoded = name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed.subtracting(CharacterSet(charactersIn: "/?#"))) else { return nil }
        return api.absolute("/api/receipts/\(encoded)")
    }

    /// Member → treasurer application; the client notifies the admins itself afterwards.
    func submitRequest(user: User, person: Person?, type: String, data: [String: JSONValue]) async throws {
        let id = String(Int64(Date().timeIntervalSince1970 * 1000))
        let personName = person?.name ?? user.fullName
        try await api.perform(.put, "/api/db", body: [
            "path": .string("requests/\(id)"),
            "value": [
                "id": .string(id),
                "type": .string(type),
                "userId": .string(user.userId),
                "personId": .string(person?.id ?? user.userId),
                "personName": .string(personName),
                "data": .object(data),
                "status": "pending",
                "timestamp": .number(Double(id) ?? 0)
            ]
        ])
        try? await api.perform(.post, "/api/notify-admins", body: ["reqType": .string(type), "personName": .string(personName)])
    }

    // MARK: Finances (treasurer)

    func stats() async throws -> FinanceStats { try await api.get("/api/stats") }

    func transactions(page: Int, search: String) async throws -> TransactionPage {
        try await api.get("/api/transactions", query: ["page": String(page), "perPage": "50", "search": search])
    }

    /// Every booking (all pages), for the financial report.
    func allTransactions() async throws -> [Transaction] {
        var all: [Transaction] = []
        var page = 1
        var pages = 1
        repeat {
            let result: TransactionPage = try await api.get("/api/transactions", query: ["page": String(page), "perPage": "500"])
            all += result.items
            pages = max(result.totalPages, 1)
            page += 1
        } while page <= pages
        return all
    }

    /// Optimistic-locking update of a person record, like the web app's runTransaction (3 attempts).
    func mutatePerson(id: String, _ mutate: (JSONValue) throws -> JSONValue) async throws {
        for attempt in 0..<3 {
            let raw: JSONValue = try await api.get("/api/db", query: ["path": "people/\(id)", "raw": "1"])
            guard var current = raw["value"], current.objectValue != nil else { throw APIError(status: 404, message: "Person nicht gefunden") }
            if current["payments"]?.arrayValue == nil { current["payments"] = .array([]) }
            if current["statusHistory"]?.arrayValue == nil { current["statusHistory"] = .array([]) }
            do {
                try await api.perform(.post, "/api/db/transaction", body: [
                    "path": .string("people/\(id)"),
                    "currentVersion": raw["version"] ?? .null,
                    "value": try mutate(current)
                ])
                return
            } catch let error as APIError where error.status == 409 && attempt < 2 {
                continue
            }
        }
    }

    /// Donations and expenses are stored as whole lists: read, change, write back.
    private func mutateCollection(_ name: String, _ change: ([JSONValue]) -> [JSONValue]) async throws {
        let current: JSONValue = try await api.get("/api/db", query: ["path": name])
        let list: [JSONValue]
        switch current {
        case .array(let items): list = items
        case .object(let map): list = map.keys.sorted().compactMap { map[$0] }
        default: list = []
        }
        try await api.perform(.put, "/api/db", body: ["path": .string(name), "value": .array(change(list.filter { !$0.isNull }))])
    }

    private static func nowId() -> Double { (Date().timeIntervalSince1970 * 1000).rounded() }

    func bookPayment(personId: String, amount: Double, date: String, note: String, standingOrder: Bool) async throws {
        try await mutatePerson(id: personId) { person in
            if standingOrder {
                return PersonRecord.append(person, to: "standingOrders", [
                    "id": .string(String(Int64(Self.nowId()))), "amount": .number(amount), "startDate": .string(date),
                    "note": .string(note), "lastAutoPayment": .null
                ])
            }
            let updated = PersonRecord.append(person, to: "payments", [
                "amount": .number(amount), "date": .string(date), "description": .string(note), "id": .number(Self.nowId())
            ])
            return PersonRecord.addingToTotal(updated, amount)
        }
    }

    /// Ends a standing order on [endDate] (also retroactively).
    func endStandingOrder(personId: String, orderId: String, endDate: String) async throws {
        try await mutatePerson(id: personId) { StandingOrders.end($0, orderId: orderId, endDate: endDate, today: Day.today()) }
    }

    /// Removes the standing order entry; payments it already booked stay.
    func deleteStandingOrder(personId: String, orderId: String) async throws {
        try await mutatePerson(id: personId) { StandingOrders.remove($0, orderId: orderId) }
    }

    func changeStatus(personId: String, status: String, date: String) async throws {
        try await mutatePerson(id: personId) { try StatusHistory.apply($0, newStatus: status, changeDate: date) }
    }

    func addDonation(amount: Double, name: String, date: String, description: String) async throws {
        try await mutateCollection("donations") { $0 + [[
            "amount": .number(amount), "name": .string(name), "date": .string(date),
            "description": .string(description.trimmingCharacters(in: .whitespaces)), "id": .number(Self.nowId())
        ]] }
    }

    func addExpense(amount: Double, issuer: String, date: String, description: String, receipts: [String]) async throws {
        let receipt: JSONValue = receipts.isEmpty ? .null
            : .string(String(decoding: (try? JSONEncoder().encode(receipts)) ?? Data("[]".utf8), as: UTF8.self))
        try await mutateCollection("expenses") { $0 + [[
            "amount": .number(amount), "issuer": .string(issuer), "description": .string(description),
            "date": .string(date), "id": .number(Self.nowId()), "receipt": receipt
        ]] }
    }

    func approveRequest(_ request: FinanceRequest) async throws {
        let amount = request.amount
        let date = request.field("date") ?? ""
        let note = request.field("note").flatMap { $0.trimmingCharacters(in: .whitespaces).isEmpty ? nil : $0 }
        switch request.type {
        case "expense":
            try await mutateCollection("expenses") { $0 + [[
                // The requester is the issuer of the expense, like for expenses booked by hand (web beta18)
                "id": .string(String(Int64(Self.nowId()))), "amount": .number(amount),
                "description": .string(request.field("description") ?? ""), "issuer": .string(request.personName),
                "date": .string(date), "receipt": request.data["receipt"] ?? .null
            ]] }
        case "payment":
            try await mutatePerson(id: request.personId) { person in
                PersonRecord.addingToTotal(PersonRecord.append(person, to: "payments", [
                    "id": .string(String(Int64(Self.nowId()))), "amount": .number(amount), "date": .string(date),
                    "description": .string(note ?? "Zahlung (Genehmigt)")
                ]), amount)
            }
        case "standing_order":
            try await mutatePerson(id: request.personId) { person in
                PersonRecord.append(person, to: "standingOrders", [
                    "id": .string(String(Int64(Self.nowId()))), "amount": .number(amount), "startDate": .string(date),
                    "note": .string(note ?? "Dauerauftrag (Genehmigt)"), "lastAutoPayment": .null
                ])
            }
        case "status":
            // Same history rewrite as a treasurer status change
            try await mutatePerson(id: request.personId) { try StatusHistory.apply($0, newStatus: request.field("newStatus") ?? "", changeDate: date) }
        default:
            break
        }
        try await patchRequest(request.id, ["status": "approved"])
    }

    func rejectRequest(id: String, reason: String) async throws {
        let text = reason.trimmingCharacters(in: .whitespaces)
        try await patchRequest(id, ["status": "rejected", "rejectionReason": .string(text.isEmpty ? "Kein Grund angegeben" : text)])
    }

    private func patchRequest(_ id: String, _ value: JSONValue) async throws {
        try await api.perform(.patch, "/api/db", body: ["path": .string("requests/\(id)"), "value": value])
    }

    // MARK: Events

    func events() async throws -> [AgoraEvent] { try await api.get("/api/events", as: LossyList<AgoraEvent>.self).items }
    func myDutyRequests() async throws -> [DutyRequest] { try await api.get("/api/events/my-requests", as: LossyList<DutyRequest>.self).items }
    func eventSettings() async -> EventSettings { (try? await api.get("/api/events/settings")) ?? EventSettings() }
    func attendees(eventId: String) async throws -> Attendees { try await api.get("/api/events/\(eventId)/attendees") }
    func candidates() async throws -> Candidates { try await api.get("/api/events/candidates") }

    func register(eventId: String, _ register: Bool) async throws {
        try await api.perform(.post, "/api/events/\(eventId)/register", body: ["action": .string(register ? "register" : "cancel")])
    }

    func removeAttendee(eventId: String, userId: String) async throws {
        try await api.perform(.delete, "/api/events/\(eventId)/attendees/\(userId)")
    }

    func respondToDuty(id: String, accept: Bool) async throws {
        try await api.perform(.post, "/api/events/duties/\(id)/respond", body: ["action": .string(accept ? "accept" : "decline")])
    }

    func claimDuty(id: String, claim: Bool) async throws {
        try await api.perform(.post, "/api/events/duties/\(id)/claim", body: claim ? [:] : ["action": "unclaim"])
    }

    func cancelDutyRequest(id: String) async throws {
        try await api.perform(.post, "/api/events/duties/\(id)/cancel-request")
    }

    func addDuty(eventId: String, roleName: String, section: String = "", userId: String? = nil, groupId: String? = nil) async throws {
        var body: JSONValue = ["roleName": .string(roleName), "sendEmail": true]
        if !section.isEmpty { body["section"] = .string(section) }
        if let userId { body["targetUserId"] = .string(userId) }
        if let groupId { body["targetGroupId"] = .string(groupId) }
        try await api.perform(.post, "/api/events/\(eventId)/duties", body: body)
    }

    func assignDuty(id: String, userId: String?, groupId: String?) async throws {
        var body: JSONValue = ["sendEmail": true]
        if let userId { body["targetUserId"] = .string(userId) }
        if let groupId { body["targetGroupId"] = .string(groupId) }
        try await api.perform(.post, "/api/events/duties/\(id)/assign", body: body)
    }

    func updateDutyNotes(id: String, notes: String) async throws {
        try await api.perform(.patch, "/api/events/duties/\(id)", body: ["notes": .string(notes)])
    }

    func deleteDuty(id: String) async throws {
        try await api.perform(.delete, "/api/events/duties/\(id)")
    }

    func uploadEventImage(jpeg: Data) async throws -> String {
        let response: UploadResponse = try await api.upload("/api/events/upload-image",
                                                            file: .init(field: "image", fileName: "cover.jpg", mimeType: "image/jpeg", data: jpeg))
        return response.url
    }

    func saveEvent(id existingId: String?, _ input: EventInput) async throws {
        var body: JSONValue = [
            "title": .string(input.title.trimmingCharacters(in: .whitespaces)),
            "date": .string(input.date), "endDate": .string(input.endDate),
            "startTime": .string(input.startTime), "endTime": .string(input.endTime),
            "location": .string(input.location.trimmingCharacters(in: .whitespaces)),
            "description": .string(input.description.trimmingCharacters(in: .whitespacesAndNewlines)),
            "eventType": .string(input.eventType), "isPinned": .bool(input.isPinned),
            "requiresRegistration": .bool(input.requiresRegistration),
            "minParticipants": .of(input.minParticipants), "maxParticipants": .of(input.maxParticipants),
            "targetGroups": .of(input.targetGroups), "imageUrl": .string(input.imageUrl)
        ]
        if existingId == nil {
            body["isRecurring"] = .bool(input.isRecurring)
            if input.isRecurring {
                body["recurringRule"] = .string(input.recurringRule)
                body["recurringCount"] = .of(input.recurringCount)
            }
            if !input.duties.isEmpty { body["duties"] = .array(input.duties.map { ["roleName": .string($0)] }) }
        }
        if let existingId {
            try await api.perform(.patch, "/api/events/\(existingId)", body: body)
        } else {
            try await api.perform(.post, "/api/events", body: body)
        }
    }

    func deleteEvent(id: String) async throws {
        try await api.perform(.delete, "/api/events/\(id)")
    }

    // MARK: Mentoring

    func threads() async throws -> [MentoringThread] { try await api.get("/api/mentoring/threads", as: LossyList<MentoringThread>.self).items }

    func messages(threadId: String) async throws -> [ChatMessage] {
        try await api.get("/api/mentoring/threads/\(threadId)/messages", as: LossyList<ChatMessage>.self).items
    }

    func sendMessage(threadId: String, text: String) async throws {
        try await api.perform(.post, "/api/mentoring/threads/\(threadId)/messages", body: ["text": .string(text)])
    }

    /// "closed", "active" (reopen) or "blocked".
    func setThreadStatus(threadId: String, _ status: String) async throws {
        try await api.perform(.patch, "/api/mentoring/threads/\(threadId)/status", body: ["status": .string(status)])
    }

    func mentors(status: String? = nil) async throws -> [Mentor] {
        try await api.get("/api/mentoring/mentors", query: status.map { ["status": $0] } ?? [:], as: LossyList<Mentor>.self).items
    }

    func myMentorProfile() async -> MyMentorProfile { (try? await api.get("/api/mentoring/my-profile")) ?? MyMentorProfile() }

    func contactMentor(userId: String, message: String) async throws -> String {
        let response: CreateThreadResponse = try await api.send(.post, "/api/mentoring/threads",
                                                                body: ["mentorId": .string(userId), "initialMessage": .string(message)])
        return response.threadId
    }

    func saveMentorProfile(isNew: Bool, bio: String, maxMentees: Int, isAccepting: Bool) async throws {
        var body: JSONValue = ["bio": .string(bio.trimmingCharacters(in: .whitespacesAndNewlines)), "max_mentees": .of(maxMentees)]
        if !isNew { body["isAccepting"] = .bool(isAccepting) }
        if isNew {
            try await api.perform(.post, "/api/mentoring/apply", body: body)
        } else {
            try await api.perform(.put, "/api/mentoring/my-profile", body: body)
        }
    }

    func setMentorStatus(recordId: String, _ status: String) async throws {
        try await api.perform(.post, "/api/mentoring/manage/\(recordId)/status", body: ["status": .string(status)])
    }

    // MARK: AI

    func aiEnabled() async -> Bool { ((try? await api.get("/api/admin/ai-status", as: AiStatus.self))?.enabled) ?? false }

    /// Streams an AI answer (`data: {"content"|"reasoning"}` lines ending with `data: [DONE]`).
    func aiChat(history: [AiMessage]) throws -> AsyncThrowingStream<AiChunk, Error> {
        var request = api.request(try api.url("/api/ai/chat"), method: .post)
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.httpBody = try api.encoder.encode(JSONValue.object(["messages": .array(history.map { ["role": .string($0.role), "content": .string($0.content)] })]))
        let lines = api.lines(request)
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for try await line in lines {
                        guard line.hasPrefix("data:") else { continue }
                        let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                        if payload == "[DONE]" { break }
                        guard let object = try? JSONDecoder().decode([String: JSONValue].self, from: Data(payload.utf8)) else { continue }
                        if let text = object["content"]?.text { continuation.yield(.content(text)) }
                        if let text = object["reasoning"]?.text { continuation.yield(.reasoning(text)) }
                        if let error = object["error"]?.text { throw APIError(status: 500, message: error) }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: Live updates

    /// Changed areas ("all", "events", "mentoring") per `data_update` event; reconnects with backoff until cancelled.
    /// Servers before 3.0.0-beta15 send no scope: that counts as "all".
    func liveUpdates() -> AsyncStream<String> {
        AsyncStream { continuation in
            let task = Task {
                var backoff: UInt64 = 2
                while !Task.isCancelled {
                    do {
                        let request = api.request(try api.url("/api/stream"))
                        var isUpdate = false
                        for try await line in api.lines(request) {
                            backoff = 2
                            if line.hasPrefix("event:") {
                                isUpdate = line.contains("data_update")
                            } else if line.hasPrefix("data:"), isUpdate {
                                continuation.yield(Self.updateScope(String(line.dropFirst(5))))
                                isUpdate = false
                            }
                        }
                    } catch let error as APIError where error.status == 401 {
                        break
                    } catch {
                        // network hiccup or proxy closing the idle connection: retry below
                    }
                    if Task.isCancelled { break }
                    try? await Task.sleep(nanoseconds: backoff * 1_000_000_000)
                    backoff = min(backoff * 2, 60)
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    static func updateScope(_ payload: String) -> String {
        guard let object = try? JSONDecoder().decode([String: JSONValue].self, from: Data(payload.trimmingCharacters(in: .whitespaces).utf8)),
              let scope = object["scope"]?.text, !scope.isEmpty else { return "all" }
        return scope
    }
}

/// JSON helpers for person records.
enum PersonRecord {
    static func append(_ person: JSONValue, to key: String, _ item: JSONValue) -> JSONValue {
        var result = person
        result[key] = .array((person[key]?.arrayValue ?? []) + [item])
        return result
    }

    static func addingToTotal(_ person: JSONValue, _ added: Double) -> JSONValue {
        var result = person
        result["totalPaid"] = .number((person["totalPaid"]?.amount ?? 0) + added)
        return result
    }
}
