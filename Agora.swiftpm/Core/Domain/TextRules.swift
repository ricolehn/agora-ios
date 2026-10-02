import Foundation

enum AiText {
    /// Separates `<think>…</think>` / `<thought>…</thought>` blocks (also an unclosed one while streaming) from the
    /// visible answer: returns (visible, thinking).
    static func splitThinking(_ content: String) -> (visible: String, thinking: String) {
        guard let regex = try? NSRegularExpression(pattern: "<(think|thought)>([\\s\\S]*?)(</\\1>|$)") else { return (content, "") }
        let range = NSRange(content.startIndex..., in: content)
        let thinking = regex.matches(in: content, range: range).compactMap { match -> String? in
            guard let part = Range(match.range(at: 2), in: content) else { return nil }
            return content[part].trimmingCharacters(in: .whitespacesAndNewlines)
        }.joined(separator: "\n")
        let visible = regex.stringByReplacingMatches(in: content, range: range, withTemplate: "")
        return (visible.trimmingCharacters(in: .whitespacesAndNewlines), thinking)
    }
}

/// Small Markdown model for event descriptions and AI answers: headings, lists, quotes, code and paragraphs as
/// blocks; inline styles (bold, italic, links, code) are left to AttributedString.
enum MarkdownBlock: Hashable, Sendable {
    case heading(level: Int, text: String)
    case paragraph(String)
    case bullet(items: [String])
    case numbered(start: Int, items: [String])
    case quote(String)
    case code(String)
    case rule

    static func parse(_ markdown: String) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        var paragraph: [String] = []
        var bullets: [String] = []
        var numbers: [String] = []
        var numberStart = 1
        var quote: [String] = []
        var code: [String]?

        func flush() {
            if !paragraph.isEmpty { blocks.append(.paragraph(paragraph.joined(separator: "\n"))); paragraph = [] }
            if !bullets.isEmpty { blocks.append(.bullet(items: bullets)); bullets = [] }
            if !numbers.isEmpty { blocks.append(.numbered(start: numberStart, items: numbers)); numbers = [] }
            if !quote.isEmpty { blocks.append(.quote(quote.joined(separator: "\n"))); quote = [] }
        }

        for rawLine in markdown.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if code != nil {
                if line.hasPrefix("```") {
                    blocks.append(.code(code!.joined(separator: "\n")))
                    code = nil
                } else {
                    code!.append(rawLine)
                }
                continue
            }
            if line.hasPrefix("```") { flush(); code = []; continue }
            if line.isEmpty { flush(); continue }
            if line == "---" || line == "***" || line == "___" { flush(); blocks.append(.rule); continue }
            if let hashes = line.firstIndex(where: { $0 != "#" }), line.hasPrefix("#") {
                let level = line.distance(from: line.startIndex, to: hashes)
                if level <= 6, line[hashes] == " " {
                    flush()
                    blocks.append(.heading(level: level, text: line[hashes...].trimmingCharacters(in: .whitespaces)))
                    continue
                }
            }
            if line.hasPrefix("- ") || line.hasPrefix("* ") || line.hasPrefix("+ ") {
                if !paragraph.isEmpty || !numbers.isEmpty || !quote.isEmpty { let keep = bullets; flush(); bullets = keep }
                bullets.append(String(line.dropFirst(2)))
                continue
            }
            if let dot = line.firstIndex(where: { $0 == "." || $0 == ")" }), let number = Int(line[..<dot]),
               line.index(after: dot) < line.endIndex, line[line.index(after: dot)] == " " {
                if !paragraph.isEmpty || !bullets.isEmpty || !quote.isEmpty { let keep = numbers; flush(); numbers = keep }
                if numbers.isEmpty { numberStart = number }
                numbers.append(line[line.index(dot, offsetBy: 2)...].trimmingCharacters(in: .whitespaces))
                continue
            }
            if line.hasPrefix(">") {
                if !paragraph.isEmpty || !bullets.isEmpty || !numbers.isEmpty { let keep = quote; flush(); quote = keep }
                quote.append(line.dropFirst().trimmingCharacters(in: .whitespaces))
                continue
            }
            if !bullets.isEmpty || !numbers.isEmpty || !quote.isEmpty { flush() }
            paragraph.append(line)
        }
        if let code { blocks.append(.code(code.joined(separator: "\n"))) }
        flush()
        return blocks
    }
}
