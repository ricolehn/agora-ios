import Foundation

// Songbook text and chords, ported from the web app (assets/songbook.js) like the Android app's SongbookLogic.kt
// (pure functions).
//
// Songs are written ChordPro style: "[G]Amazing [D/F#]grace" puts a chord above the syllable it stands in front
// of, "# Chorus" (or {c: Chorus}, {start_of_chorus}) starts a section, "> twice" is a note for the musicians.
// Only real chords are transposed: "[Bridge]" or "[N.C.]" stay as they are. German songbooks write H for B and B
// for Bb; a song that uses H keeps that notation.

private func pattern(_ text: String, _ options: NSRegularExpression.Options = []) -> NSRegularExpression {
    // The patterns are constants of this file: a typo is a programming error
    try! NSRegularExpression(pattern: text, options: options)
}

private extension NSRegularExpression {
    func whole(_ text: String) -> NSRange { NSRange(location: 0, length: (text as NSString).length) }

    func matches(_ text: String) -> Bool { firstMatch(in: text, range: whole(text)) != nil }

    /// The groups of the first match (nil for a group that did not take part), or nil without a match.
    func groups(_ text: String) -> [String?]? {
        guard let match = firstMatch(in: text, range: whole(text)) else { return nil }
        let ns = text as NSString
        return (0..<match.numberOfRanges).map { index in
            let range = match.range(at: index)
            return range.location == NSNotFound ? nil : ns.substring(with: range)
        }
    }

    /// One group of every match.
    func all(_ text: String, group: Int) -> [String] {
        let ns = text as NSString
        return matches(in: text, range: whole(text)).compactMap { match in
            let range = match.range(at: group)
            return range.location == NSNotFound ? nil : ns.substring(with: range)
        }
    }

    func replacing(_ text: String, with template: String) -> String {
        stringByReplacingMatches(in: text, range: whole(text), withTemplate: template)
    }

    func replacingFirst(_ text: String, with replacement: String) -> String {
        guard let match = firstMatch(in: text, range: whole(text)) else { return text }
        return (text as NSString).replacingCharacters(in: match.range, with: replacement)
    }
}

private let sharps = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
private let flatNames = ["C", "Db", "D", "Eb", "E", "F", "Gb", "G", "Ab", "A", "Bb", "B"]
private let natural: [Character: Int] = ["C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11, "H": 11]

// Major keys written with flats (index of the tonic): F, Bb, Eb, Ab, Db; Gb/F# follows the original spelling
private let flatMajorKeys: Set<Int> = [5, 10, 3, 8, 1]

// Root, accidental, quality / extensions, optional bass note. The quality only allows chord vocabulary, so words
// starting with A-H ("Bridge", "Chorus", "End") are not chords.
private let chordPattern = pattern(#"^([A-H])(#|b)?((?:maj|min|dim|aug|sus|add|alt|no|m|M|Δ|°|ø|\+|-|[0-9]|[#b](?=[0-9])|\(|\)|,|\.)*)(?:/([A-H])(#|b)?)?$"#)
private let bracketed = pattern(#"\[([^\]]+)\]"#)
private let directiveName = pattern(#"^[a-z_]{1,24}$"#)
private let flatStart = pattern(#"^[A-G]b"#)

struct ChordNote: Hashable {
    let root: Character
    let accidental: String
}

/// The parts of a chord like "F#m7/C#".
struct Chord: Hashable {
    let root: Character
    let accidental: String
    let quality: String
    let bass: ChordNote?
}

/// How chords of one song are written at a given transposition.
struct Spelling: Hashable {
    var flats = false
    var german = false
}

/// One chord with the text that follows it; `chord` is nil where the text continues without a new chord.
struct SongSegment: Hashable {
    let chord: String?
    let text: String
}

/// A line of a song.
enum SongLine: Hashable {
    case gap
    /// A section heading; `label` names a ChordPro section without its own text: chorus, verse, bridge, tab.
    case section(text: String, label: String?)
    case note(String)
    case text(String)
    /// Lyrics with chords: one inner list per word, so a line can wrap between words.
    case chords([[SongSegment]])
}

enum SongbookLogic {
    /// The parts of a chord, or nil if `text` is not a chord.
    static func parseChord(_ text: String?) -> Chord? {
        let value = (text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, value.count <= 24, let groups = chordPattern.groups(value), let root = groups[1]?.first else { return nil }
        let bass = groups[4].flatMap { $0.first }.map { ChordNote(root: $0, accidental: groups[5] ?? "") }
        return Chord(root: root, accidental: groups[2] ?? "", quality: groups[3] ?? "", bass: bass)
    }

    /// Pitch class 0-11 of a note; in German notation B is Bb and H is B.
    private static func noteIndex(_ root: Character, _ accidental: String, german: Bool) -> Int {
        let base = german && root == "B" ? 10 : (natural[root] ?? 0)
        let shift = accidental == "#" ? 1 : (accidental == "b" ? -1 : 0)
        return (base + shift + 12) % 12
    }

    private static func noteName(_ index: Int, flats: Bool, german: Bool) -> String {
        let name = (flats ? flatNames : sharps)[((index % 12) + 12) % 12]
        guard german else { return name }
        // German: Bb is written B, B is written H
        if name == "Bb" || name == "A#" { return "B" }
        if name == "B" { return "H" }
        return name
    }

    /// Whether a song is written in German notation (it uses H).
    private static func isGerman(_ chords: [String]) -> Bool { chords.contains { $0.hasPrefix("H") || $0.contains("/H") } }

    private struct Key {
        let index: Int
        let minor: Bool
    }

    /// The key of a song: its "key" field, else the first chord (minor if it is one).
    private static func songKey(_ declared: String?, _ chords: [String], german: Bool) -> Key? {
        guard let source = parseChord(declared) ?? chords.lazy.compactMap({ parseChord($0) }).first else { return nil }
        return Key(index: noteIndex(source.root, source.accidental, german: german),
                   minor: source.quality.hasPrefix("m") && !source.quality.hasPrefix("maj"))
    }

    /// Flats or sharps in the target key (minor keys follow their relative major).
    private static func prefersFlats(_ key: Key?, steps: Int, originalFlats: Bool) -> Bool {
        guard let key else { return originalFlats }
        let tonic = (key.index + steps + 120) % 12
        let major = key.minor ? (tonic + 3) % 12 : tonic
        if major == 6 { return originalFlats } // F# / Gb: keep what the song used
        return flatMajorKeys.contains(major)
    }

    /// One chord moved by `steps` semitones (unchanged for non-chords and steps 0).
    static func transposeChord(_ text: String, steps: Int, spelling: Spelling = Spelling()) -> String {
        guard steps != 0, let chord = parseChord(text) else { return text }
        let root = noteName(noteIndex(chord.root, chord.accidental, german: spelling.german) + steps, flats: spelling.flats, german: spelling.german)
        let bass = chord.bass.map { "/" + noteName(noteIndex($0.root, $0.accidental, german: spelling.german) + steps, flats: spelling.flats, german: spelling.german) } ?? ""
        return root + chord.quality + bass
    }

    /// Spelling rules for one song at `steps`.
    static func spelling(content: String?, declaredKey: String?, steps: Int) -> Spelling {
        let chords = bracketed.all(content ?? "", group: 1).filter { parseChord($0) != nil }
        let key = declaredKey ?? ""
        let german = isGerman(chords) || key.hasPrefix("H")
        let originalFlats = chords.contains { flatStart.matches($0) } || flatStart.matches(key)
        return Spelling(flats: prefersFlats(songKey(declaredKey, chords, german: german), steps: steps, originalFlats: originalFlats), german: german)
    }

    /// The key label shown above the song, transposed like its chords.
    static func transposedKey(_ declaredKey: String?, content: String?, steps: Int) -> String {
        guard let declaredKey, !declaredKey.isEmpty else { return "" }
        return transposeChord(declaredKey, steps: steps, spelling: Self.spelling(content: content, declaredKey: declaredKey, steps: steps))
    }

    /// A transposition step -6...5 after moving `steps` by `delta` semitones (like the song page of the web app).
    static func step(_ steps: Int, by delta: Int) -> Int { (((steps + delta + 6) % 12) + 12) % 12 - 6 }

    // MARK: The song as lines

    private struct Directive {
        let name: String
        let value: String
    }

    /// A ChordPro directive "{name: value}".
    private static func directive(_ line: String) -> Directive? {
        guard line.hasPrefix("{"), line.hasSuffix("}"), line.count >= 2 else { return nil }
        let inner = String(line.dropFirst().dropLast())
        let colon = inner.firstIndex(of: ":")
        let name = (colon.map { String(inner[..<$0]) } ?? inner).trimmingCharacters(in: .whitespaces).lowercased()
        guard directiveName.matches(name) else { return nil }
        let value = colon.map { String(inner[inner.index(after: $0)...]).trimmingCharacters(in: .whitespaces) } ?? ""
        return Directive(name: name, value: value)
    }

    private static let sectionDirectives = [
        "start_of_chorus": "chorus", "soc": "chorus",
        "start_of_verse": "verse", "sov": "verse",
        "start_of_bridge": "bridge", "sob": "bridge",
        "start_of_tab": "tab", "sot": "tab"
    ]
    private static let commentDirectives: Set<String> = ["c", "comment", "ci", "comment_italic"]
    private static let sectionHash = pattern(#"^#+\s*"#)
    private static let noteMark = pattern(#"^>\s*"#)
    private static let onlyBracket = pattern(#"^\[([^\]]+)\]$"#)
    private static let anyBracket = pattern(#"\[[^\]]*\]"#)
    private static let hasChord = pattern(#"\[[^\]]+\]"#)

    /// The song as lines (chords transposed by `steps`; without `chords` only the lyrics).
    static func parse(_ content: String?, steps: Int = 0, declaredKey: String? = "", chords: Bool = true) -> [SongLine] {
        let rules = Self.spelling(content: content, declaredKey: declaredKey, steps: steps)
        var lines: [SongLine] = []
        for raw in (content ?? "").components(separatedBy: "\n") {
            var line = raw
            while let last = line.last, last.isWhitespace { line.removeLast() }
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                // At most one gap in a row
                if let last = lines.last, last != .gap { lines.append(.gap) }
                continue
            }
            if trimmed.hasPrefix("#") {
                lines.append(.section(text: sectionHash.replacingFirst(trimmed, with: ""), label: nil))
                continue
            }
            if let command = directive(trimmed) {
                if commentDirectives.contains(command.name) {
                    lines.append(.section(text: command.value, label: nil))
                } else if let label = sectionDirectives[command.name] {
                    lines.append(.section(text: command.value, label: label))
                }
                // Everything else ({title}, {key}, {capo}, {end_of_chorus}, …) is not shown
                continue
            }
            if trimmed.hasPrefix(">") {
                lines.append(.note(noteMark.replacingFirst(trimmed, with: "")))
                continue
            }
            // "[Bridge]" alone on a line is a section name, not a chord
            if let groups = onlyBracket.groups(trimmed), let name = groups[1], parseChord(name) == nil {
                lines.append(.section(text: name.trimmingCharacters(in: .whitespaces), label: nil))
                continue
            }
            let lyrics = anyBracket.replacing(line, with: "")
            if !hasChord.matches(line) || !chords {
                // A line of chords only says nothing without its chords
                if lyrics.trimmingCharacters(in: .whitespaces).isEmpty { continue }
                lines.append(.text(lyrics))
                continue
            }
            lines.append(.chords(splitWords(line, steps: steps, spelling: rules)))
        }
        while let last = lines.last, last == .gap { lines.removeLast() }
        return lines
    }

    /// "[G]Amazing [D]grace" → [[G "Amazing "], [D "grace"]].
    private static func splitWords(_ line: String, steps: Int, spelling: Spelling) -> [[SongSegment]] {
        // The line in parts: chord markers and the text between them
        let ns = line as NSString
        var parts: [(isChord: Bool, value: String)] = []
        var last = 0
        for match in hasChord.matches(in: line, range: NSRange(location: 0, length: ns.length)) {
            if match.range.location > last {
                parts.append((false, ns.substring(with: NSRange(location: last, length: match.range.location - last))))
            }
            parts.append((true, String(ns.substring(with: match.range).dropFirst().dropLast())))
            last = match.range.location + match.range.length
        }
        if last < ns.length { parts.append((false, ns.substring(from: last))) }

        var segments: [SongSegment] = []
        var pending: String?
        for part in parts {
            if part.isChord {
                if let chord = pending { segments.append(SongSegment(chord: chord, text: "")) }
                pending = transposeChord(part.value, steps: steps, spelling: spelling)
            } else {
                segments.append(SongSegment(chord: pending, text: part.value))
                pending = nil
            }
        }
        if let chord = pending { segments.append(SongSegment(chord: chord, text: "")) }

        // Break segments after spaces; a word that continues across a chord ("Ama[G]zing") stays one word
        var words: [[SongSegment]] = []
        var word: [SongSegment] = []
        for segment in segments {
            if segment.text.isEmpty {
                word.append(SongSegment(chord: segment.chord, text: ""))
                continue
            }
            var pieces: [String] = []
            var current = ""
            for character in segment.text {
                current.append(character)
                if character.isWhitespace {
                    pieces.append(current)
                    current = ""
                }
            }
            if !current.isEmpty { pieces.append(current) }
            for (index, piece) in pieces.enumerated() {
                word.append(SongSegment(chord: index == 0 ? segment.chord : nil, text: piece))
                if piece.last?.isWhitespace == true {
                    words.append(word)
                    word = []
                }
            }
        }
        if !word.isEmpty { words.append(word) }
        return words
    }

    /// A line of chords alone ("[G] [D] [Em]") has no lyric row.
    static func chordsOnly(_ words: [[SongSegment]]) -> Bool {
        words.allSatisfy { word in word.allSatisfy { $0.text.trimmingCharacters(in: .whitespaces).isEmpty } }
    }

    // MARK: Search

    private static let metaLines = pattern(#"^\s*[#>{].*$"#, [.anchorsMatchLines])

    /// Lower case, no accents, single spaces.
    static func normalizeSearch(_ text: String?) -> String {
        (text ?? "").folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
            .components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " ")
    }

    /// Text to search in: title, writers, CCLI number and the lyrics without chords; lower case, no accents.
    static func searchText(_ song: Song) -> String {
        let lyrics = metaLines.replacing(anyBracket.replacing(song.content, with: ""), with: " ")
        return normalizeSearch([song.title, song.artist, song.ccli, song.copyright, lyrics].filter { !$0.isEmpty }.joined(separator: " "))
    }
}
