import Foundation

/// A step of the AI's work on one reply, as the thinking field lists them (web: assets/aiReply.js, Android AiReply.kt).
enum AiStep: Equatable, Sendable {
    /// What the model thought (reasoning sent apart, or a `<think>` block of text before a lookup).
    case thought(String)
    /// What the model wrote before it looked something up: a note on the way, not the answer.
    case note(String)
    /// A lookup of the server (CALDERA) and, once it ran, what it found.
    case lookup(AiLookup, done: AiLookupDone?)
}

/// The steps of one reply, built up from what the server streams (web: createReplyWork): thoughts, text and – from
/// CALDERA on – the lookups the server makes for the AI and what they found. Text written before a lookup was a note on
/// the way: when the lookup comes it moves into the steps (with any `<think>` block in it), and `content` is the text
/// of the round after the last lookup – the answer.
struct AiReplyWork: Equatable, Sendable {
    private(set) var steps: [AiStep] = []
    private(set) var content = ""
    private(set) var lookups = 0

    mutating func add(_ chunk: AiChunk) {
        switch chunk {
        case .reasoning(let text):
            guard !text.isEmpty else { return }
            if case .thought(let before)? = steps.last {
                steps[steps.count - 1] = .thought(before + text)
            } else {
                steps.append(.thought(text))
            }
        case .content(let text):
            content += text
        case .lookup(let lookup):
            let split = AiText.splitThinking(content)
            if !split.thinking.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { steps.append(.thought(split.thinking)) }
            if !split.visible.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { steps.append(.note(split.visible)) }
            content = ""
            lookups += 1
            steps.append(.lookup(lookup, done: nil))
        case .lookupDone(let done):
            // The newest lookup with this id (or without one) that has not found anything yet
            let at = steps.lastIndex { step in
                if case .lookup(let lookup, nil) = step { return done.id == nil || lookup.id == done.id }
                return false
            }
            if let at, case .lookup(let lookup, _) = steps[at] { steps[at] = .lookup(lookup, done: done) }
        }
    }
}

/// What the line above a reply says while the AI works: the title of what it thinks, or the lookup it is on.
enum AiLiveLabel: Equatable, Sendable {
    case thought(String)
    case lookup(AiLookup)
}

/// The words of the line above a reply (web: assets/aiReply.js, Android AiReply.kt – tested alike).
enum AiReplyText {
    /// A space as the web app's `\s` knows it: every Unicode space, the no-break ones too. Spelled out: ICU has no flag
    /// for it (Android's `(?U)` closed the app there).
    private static let space = #"\t\n\u000B\f\r\p{Z}﻿"#

    private static func regex(_ pattern: String, _ options: NSRegularExpression.Options = []) -> NSRegularExpression {
        // The patterns are constants: a mistake in one is a programming error the tests catch
        try! NSRegularExpression(pattern: pattern, options: options)
    }

    /// Interjections a thought often starts with ("Okay, ...", "Gut, ..."): they say nothing about what is being done.
    private static let filler = regex(#"^(?:(?:ok(?:ay)?|so|alright|all right|well|hmm+|right|also|gut|also gut|alles klar|na gut)[,.!:]\s*)+"#,
                                      .caseInsensitive)
    private static let marks = regex(#"[*_`#>]+"#)
    private static let spaces = regex("[\(space)]+")
    /// A list sign before a line ("- ", "• ", "2. ").
    private static let listSign = regex(#"^(?:[-•–]|\d+[.)])\s+"#)
    private static let titleEnd = regex(#"[\s.:;,!?…。-]+$"#)
    private static let cutEnd = regex(#"[\s,;:.-]+$"#)
    /// A title says something from this many characters on ("Hmm." and "Yes." do not).
    private static let minTitle = 8
    /// Where a sentence ends: with its line, or with . ! ? … before the next one, which begins with something else than
    /// a small letter ("e.g. the" and "3.50" end nothing).
    private static let sentenceEnd = regex(#"[.!?…]+["”“’')\]]*(?="# + "[\(space)]+[^a-zäöüßàâçéèêëîïôûùÿñæœ\(space)])" + #"|[。！？]+|\n+"#)
    /// Headings of the thoughts ("**Calculating the monthly expenses**", "## ..."), once their line is over – or the text.
    private static func headings(_ lineEnd: String) -> NSRegularExpression {
        regex(#"(?:^|\n)[ \t]*(?:#{1,6}[ \t]+([^\n]+)|\*\*([^*\n]{3,120})\*\*[ \t]*)"# + lineEnd)
    }
    private static let headingsSettled = headings(#"(?=\n|$)"#)
    private static let headingsGrowing = headings(#"(?=\n)"#)

    private static func replacing(_ regex: NSRegularExpression, in text: String, with template: String) -> String {
        regex.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: template)
    }

    private static func plain(_ text: String) -> String {
        replacing(spaces, in: replacing(marks, in: text, with: ""), with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func titleOf(_ text: String) -> String {
        replacing(titleEnd, in: replacing(filler, in: replacing(listSign, in: plain(text), with: ""), with: ""), with: "")
    }

    private static func capitalized(_ text: String) -> String { text.prefix(1).uppercased() + text.dropFirst() }

    /// [text] cut at a word to at most [max] characters.
    static func shorten(_ text: String, max: Int = 72) -> String {
        guard text.count > max else { return text }
        let cut = String(text.prefix(max - 1))
        var kept = cut
        if let space = cut.lastIndex(of: " "), Double(cut.distance(from: cut.startIndex, to: space)) > Double(max) * 0.6 {
            kept = String(cut[..<space])
        }
        return replacing(cutEnd, in: kept, with: "") + "…"
    }

    /// The finished sentences of [text]; [settled]: nothing more comes, so what stands at the end is finished too.
    private static func finishedSentences(_ text: String, settled: Bool) -> [String] {
        let whole = text as NSString
        var sentences: [String] = []
        var start = 0
        for match in sentenceEnd.matches(in: text, range: NSRange(location: 0, length: whole.length)) {
            let end = match.range.location + match.range.length
            sentences.append(whole.substring(with: NSRange(location: start, length: end - start)))
            start = end
        }
        if settled { sentences.append(whole.substring(from: start)) }
        return sentences
    }

    /// What the model is thinking about, as a short title from its thoughts so far: the newest heading, else its newest
    /// sentence. Only what is finished counts, so the title never writes itself letter by letter. [settled]: the thoughts
    /// are complete, their last line counts as well. "" when there is nothing to say yet.
    static func liveTitle(_ thinking: String, max: Int = 72, settled: Bool = true) -> String {
        let text = String(thinking.suffix(3_000))
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return "" }
        let whole = text as NSString
        var title = ""
        for match in (settled ? headingsSettled : headingsGrowing).matches(in: text, range: NSRange(location: 0, length: whole.length)) {
            let heading = match.range(at: 1).location != NSNotFound ? match.range(at: 1) : match.range(at: 2)
            title = titleOf(whole.substring(with: heading))
        }
        if title.isEmpty {
            for sentence in finishedSentences(text, settled: settled).reversed() {
                let candidate = titleOf(sentence)
                if candidate.count >= minTitle {
                    title = candidate
                    break
                }
            }
        }
        return title.isEmpty ? "" : shorten(capitalized(title), max: max)
    }

    /// A lookup's line in the model's own words, cleaned and cut – nil when it gave none.
    static func lookupStep(_ lookup: AiLookup) -> String? {
        guard let step = lookup.step.map(plain), !step.isEmpty else { return nil }
        return shorten(capitalized(step), max: 90)
    }

    /// What the reply's top line says while the AI works: the newest step it is on – a lookup (running, or the last one
    /// while the model reads its results), or the title of what it is thinking – nil when nothing is known yet.
    /// [content]: the text of the current round; [inlineThinking]: a `<think>` block in it still being written.
    static func liveLabel(steps: [AiStep], content: String, inlineThinking: String = "") -> AiLiveLabel? {
        let inline = liveTitle(inlineThinking, settled: false)
        if !inline.isEmpty { return .thought(inline) }
        // Only the newest thoughts can still be growing – and not even they once the text of this round has begun
        let growing = content.isEmpty ? steps.count - 1 : -1
        for index in steps.indices.reversed() {
            let title: String
            switch steps[index] {
            case .lookup(let lookup, _): return .lookup(lookup)
            case .thought(let text): title = liveTitle(text, settled: index != growing)
            case .note(let text): title = liveTitle(text)
            }
            if !title.isEmpty { return .thought(title) }
        }
        return nil
    }

    /// What a lookup reads: "Ausgaben 2019–2024 „Blumen“" (web: lookupWhat).
    static func lookupWhat(_ lookup: AiLookup) -> String {
        var parts = [toolName(lookup.tool)]
        switch (lookup.from, lookup.to) {
        case let (from?, to?): parts.append(from == to ? from : "\(from)–\(to)")
        case let (from?, nil): parts.append(String(localized: "seit \(from)"))
        case let (nil, to?): parts.append(String(localized: "bis \(to)"))
        case (nil, nil): break
        }
        if let about = lookup.about { parts.append("„\(about)“") }
        return parts.joined(separator: " ")
    }

    /// A lookup's line: the model's own words when it gave some, else what is looked up ("Schlägt Ausgaben nach").
    static func lookupTitle(_ lookup: AiLookup) -> String {
        lookupStep(lookup) ?? String(localized: "Schlägt \(lookupWhat(lookup)) nach")
    }

    private static func toolName(_ tool: String) -> String {
        switch tool {
        case "payments": return String(localized: "Zahlungen")
        case "expenses": return String(localized: "Ausgaben")
        case "donations": return String(localized: "Spenden")
        case "money": return String(localized: "Geld")
        case "members": return String(localized: "Mitglieder")
        case "events": return String(localized: "Termine")
        case "money_totals": return String(localized: "Summen")
        case "finance_changes": return String(localized: "Änderungsprotokoll")
        default: return String(localized: "Daten")
        }
    }

    /// What a finished lookup found: "12 Einträge · 345,50 €" – or that it was not allowed or failed; nil while it runs.
    static func lookupFound(_ done: AiLookupDone?, money: (Double) -> String) -> String? {
        guard let done else { return nil }
        if let error = done.error { return error == "forbidden" ? String(localized: "nicht erlaubt") : String(localized: "fehlgeschlagen") }
        guard let count = done.count else { return nil }
        let one = count == 1
        let found: String
        switch done.unit {
        case "entries": found = one ? String(localized: "1 Eintrag") : String(localized: "\(count) Einträge")
        case "events": found = one ? String(localized: "1 Termin") : String(localized: "\(count) Termine")
        case "changes": found = one ? String(localized: "1 Änderung") : String(localized: "\(count) Änderungen")
        case "members": found = one ? String(localized: "1 Mitglied") : String(localized: "\(count) Mitglieder")
        case "periods": found = one ? String(localized: "1 Zeitraum") : String(localized: "\(count) Zeiträume")
        default: return nil
        }
        var parts = [found]
        if let eur = done.eur { parts.append(money(eur)) }
        if done.cut { parts.append(String(localized: "gekürzt")) }
        return parts.joined(separator: " · ")
    }

    /// The line once the reply is complete: "Nachgedacht" or "Nachgedacht · 2× nachgeschlagen".
    static func doneTitle(lookups: Int) -> String {
        lookups > 0 ? String(localized: "Nachgedacht · \(lookups)× nachgeschlagen") : String(localized: "Nachgedacht")
    }
}
