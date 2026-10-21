import Foundation

/// Addresses of events, made like the web app makes them (assets/app.js: slugify, itemSlug, eventShareUrl) and like
/// Android's EventLinks, so a link shared from the app opens the same page: /events/<title>, the date or the id added
/// when titles repeat, and the share key (?share=) while people without an account may open the event.
enum EventLinks {
    private static let notLetterOrDigit = try! NSRegularExpression(pattern: #"[^\p{L}\p{N}]+"#)

    /// The title as a path part: letters and digits kept, every run of anything else one "_", at most 80 UTF-16 code
    /// units (JavaScript's String.slice).
    static func slugify(_ text: String) -> String {
        let trimmed = text.precomposedStringWithCanonicalMapping.trimmingCharacters(in: .whitespacesAndNewlines)
        let replaced = notLetterOrDigit.stringByReplacingMatches(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed), withTemplate: "_")
        let cleaned = replaced.trimmingCharacters(in: CharacterSet(charactersIn: "_"))
        return String(decoding: Array(cleaned.utf16.prefix(80)), as: UTF16.self)
    }

    private static func titleSlug(_ event: AgoraEvent) -> String {
        let slug = slugify(event.title)
        return slug.isEmpty ? event.id : slug
    }

    /// The readable name of [event] among [events]: its title; when titles repeat, the date or the id tells them apart.
    static func slug(_ event: AgoraEvent, among events: [AgoraEvent]) -> String {
        let base = titleSlug(event)
        let twins = events.filter { titleSlug($0) == base }
        if twins.count <= 1 { return base }
        if !event.date.isEmpty && twins.filter({ $0.date == event.date }).count == 1 { return "\(base)_\(event.date)" }
        return "\(base)~\(event.id)"
    }

    /// The link to share: the members' address, with the share key while the switch is on.
    static func shareURL(baseURL: String, event: AgoraEvent, among events: [AgoraEvent]) -> String {
        let url = "\(baseURL.droppingSuffix("/"))/events/\(encode(slug(event, among: events)))"
        guard event.isPublic == true, !event.publicToken.isEmpty else { return url }
        return "\(url)?share=\(encode(event.publicToken))"
    }

    // Like encodeURIComponent: ASCII letters, digits and - _ . ! ~ * ' ( ) stay, everything else is UTF-8 percent-encoded
    private static let unreserved = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_.!~*'()")

    private static func encode(_ text: String) -> String { text.addingPercentEncoding(withAllowedCharacters: unreserved) ?? text }
}
