import SwiftUI

/// Markdown like the web app (headings, bold, lists, links) for event descriptions and AI answers.
struct MarkdownView: View {
    let text: String
    var fontSize: CGFloat = 15
    var color: Color = Palette.text

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(MarkdownBlock.parse(text).enumerated()), id: \.offset) { _, block in
                blockView(block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .tint(Palette.primary)
    }

    @ViewBuilder
    private func blockView(_ block: MarkdownBlock) -> some View {
        switch block {
        case .heading(let level, let text):
            inline(text)
                .font(.system(size: level == 1 ? fontSize + 5 : level == 2 ? fontSize + 3 : fontSize + 1, weight: .heavy))
                .padding(.top, 2)
                .accessibilityAddTraits(.isHeader)
        case .paragraph(let text):
            inline(text).font(.system(size: fontSize)).lineSpacing(3)
        case .bullet(let items):
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("•").font(.system(size: fontSize, weight: .bold)).foregroundStyle(Palette.primary)
                        inline(item).font(.system(size: fontSize))
                    }
                }
            }
        case .numbered(let start, let items):
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("\(start + index).").font(.system(size: fontSize, weight: .semibold)).foregroundStyle(Palette.textSecondary).monospacedDigit()
                        inline(item).font(.system(size: fontSize))
                    }
                }
            }
        case .quote(let text):
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 2).fill(Palette.primary.opacity(0.5)).frame(width: 3)
                inline(text).font(.system(size: fontSize)).foregroundStyle(Palette.textSecondary)
            }
            .fixedSize(horizontal: false, vertical: true)
        case .code(let text):
            ScrollView(.horizontal, showsIndicators: false) {
                Text(text).font(.system(size: fontSize - 2, design: .monospaced)).foregroundStyle(Palette.text).textSelection(.enabled)
                    .padding(10)
            }
            .background(Palette.surfaceAlt, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        case .rule:
            Hairline().padding(.vertical, 4)
        }
    }

    private func inline(_ text: String) -> Text {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace, failurePolicy: .returnPartiallyParsedIfPossible)
        let attributed = (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
        return Text(attributed).foregroundColor(color)
    }
}
