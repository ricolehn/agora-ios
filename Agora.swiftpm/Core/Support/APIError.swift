import Foundation

/// Error returned by the Agora backend; the message is usually German and can be shown as is.
struct APIError: LocalizedError, Sendable {
    let status: Int
    let message: String
    /// API v2's error code (`invalid`, `conflict`, `rate_limited`, `unavailable` …); `unavailable` also for the old API's
    /// answer of a server that starts or upgrades its database (`starting: true`).
    let code: String?
    /// With `invalid`: the value of the request that did not fit, as the request named it (`details.amount`).
    let field: String?

    init(status: Int, message: String, code: String? = nil, field: String? = nil) {
        self.status = status
        self.message = message
        self.code = code
        self.field = field
    }

    var errorDescription: String? { message }

    /// A server that starts or upgrades its database (CALDERA): it answers again in a few seconds.
    var isStarting: Bool { code == "unavailable" }

    static let generic = "Etwas ist schiefgelaufen. Bitte erneut versuchen."

    /// Text for the user: the app's own words for what it knows (like Android's `knownErrorText`), else the server's
    /// message, else a generic one.
    static func text(_ error: Error) -> String {
        guard let api = error as? APIError else { return generic }
        if api.isStarting { return String(localized: "Der Server startet gerade oder aktualisiert seine Datenbank. Bitte gleich noch einmal versuchen.") }
        if api.code == "rate_limited" { return String(localized: "Zu viele Anfragen auf einmal. Bitte einen Moment warten und erneut versuchen.") }
        if api.code == "conflict" { return String(localized: "Das wurde inzwischen von jemand anderem geändert. Bitte neu laden und erneut versuchen.") }
        if !api.message.trimmingCharacters(in: .whitespaces).isEmpty { return api.message }
        return generic
    }

    /// The error of an answer outside 2xx: API v2's `{error: {code, message, field}}`, the old API's `{error}` /
    /// `{message}` (with `starting: true` while the server starts), else the plain text (not HTML or JSON) up to 200
    /// characters, else "HTTP <status>". Like Android's `AgoraApi.errorOf`; the old API's bare 409 and 429 get the
    /// codes v2 would send, so they are worded in German as well.
    static func parse(status: Int, body: Data) -> APIError {
        let object = try? JSONDecoder().decode([String: JSONValue].self, from: body)
        if let error = object?["error"], error.objectValue != nil {
            let message = error["message"]?.text.flatMap { $0.trimmingCharacters(in: .whitespaces).isEmpty ? nil : $0 } ?? "HTTP \(status)"
            return APIError(status: status, message: message, code: error["code"]?.text, field: error["field"]?.text)
        }
        let fromJSON = (object?["error"]?.text ?? object?["message"]?.text).flatMap { $0.trimmingCharacters(in: .whitespaces).isEmpty ? nil : $0 }
        let text = String(decoding: body, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        let plain = String(text.prefix(200))
        let message = fromJSON ?? (plain.isEmpty || plain.hasPrefix("<") || plain.hasPrefix("{") ? "HTTP \(status)" : plain)
        let starting = object?["starting"]?.boolValue == true || object?["starting"]?.text == "true"
        let code: String? = starting ? "unavailable" : status == 409 ? "conflict" : status == 429 ? "rate_limited" : nil
        return APIError(status: status, message: message, code: code)
    }
}

extension String {
    func droppingSuffix(_ suffix: String) -> String {
        var result = self
        while result.hasSuffix(suffix) { result.removeLast(suffix.count) }
        return result
    }

    func droppingPrefix(_ prefix: String) -> String {
        var result = self
        while result.hasPrefix(prefix) { result.removeFirst(prefix.count) }
        return result
    }
}
