import Foundation

/// Error returned by the Agora backend; the message is usually German and can be shown as is.
struct APIError: LocalizedError, Sendable {
    let status: Int
    let message: String

    var errorDescription: String? { message }

    static let generic = "Etwas ist schiefgelaufen. Bitte erneut versuchen."

    /// Text for the user: the server's message, else a generic one.
    static func text(_ error: Error) -> String {
        if let api = error as? APIError, !api.message.trimmingCharacters(in: .whitespaces).isEmpty { return api.message }
        return generic
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
