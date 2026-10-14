import SwiftUI

/// The song page of the web app: title and songwriter on top, the key as a chip (it shows the transposed key too),
/// the song with its chords above the syllables, CCLI notes after the last line, and a floating control pill:
/// semitone down / key (tap: back to the original key) / semitone up, chords on/off and text size.
/// The key starts as written whenever a song opens; chords and size are remembered.
struct SongPageView: View {
    let model: SongbookModel
    let songId: String
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var sizeClass
    @AppStorage("agora.songbook.chords") private var chords = true
    @AppStorage("agora.songbook.size") private var size = 0
    @State private var steps = 0
    @State private var editing: SongEditTarget?
    /// Set when the song was deleted in the editor: the page closes once the sheet is gone.
    @State private var deleted = false

    var body: some View {
        Group {
            if let song = model.song(songId) {
                page(song)
            } else {
                EmptyState(systemImage: "music.note", title: "Lied nicht gefunden")
            }
        }
        .background(Palette.background.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editing, onDismiss: { if deleted { dismiss() } }) { target in
            SongEditorView(model: model, song: target.song) { deleted = true }
        }
    }

    private func page(_ song: Song) -> some View {
        let key = SongbookLogic.transposedKey(song.key, content: song.content, steps: steps)
        let shift = (steps > 0 ? "+" : "") + "\(steps)"
        let lines = SongbookLogic.parse(song.content, steps: steps, declaredKey: song.key, chords: chords)
        let fontSize = (sizeClass == .regular ? 19.0 : 16.0) * (1 + Double(size) * 0.12)
        return ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(song.title).font(.system(size: 26, weight: .bold)).tracking(-0.5).foregroundStyle(Palette.text)
                        .accessibilityAddTraits(.isHeader)
                    if !song.artist.isEmpty {
                        Text(song.artist).font(.system(size: 15)).foregroundStyle(Palette.textSecondary)
                    }
                }
                .padding(.bottom, 12)
                if let fact = keyFact(song, key: key, shift: shift) {
                    Text(fact)
                        .font(.system(size: 12.5, weight: .bold))
                        .foregroundStyle(steps != 0 ? .white : Palette.primary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                        .background {
                            if steps != 0 { Capsule().fill(Palette.button) } else { Capsule().fill(Palette.primary.opacity(0.12)) }
                        }
                        .padding(.bottom, 16)
                }
                ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                    SongLineView(line: line, fontSize: fontSize, first: index == 0)
                }
                ccli(song)
            }
            .textSelection(.enabled)
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 120)
            .frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .overlay(alignment: .bottom) {
            controls(keyLabel: key.isEmpty ? (steps != 0 ? shift : "♪") : key)
                .padding(.bottom, 16)
        }
        .toolbar {
            if model.canManage {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { editing = SongEditTarget(song: song) } label: { Image(systemName: "square.and.pencil") }
                        .accessibilityLabel("Lied bearbeiten")
                }
            }
        }
    }

    /// The key at a glance; a transposed key stays visible here too.
    private func keyFact(_ song: Song, key: String, shift: String) -> String? {
        if steps != 0 {
            return key.isEmpty ? String(localized: "Um \(shift) Halbtöne transponiert") : String(localized: "Tonart \(key) (\(shift))")
        }
        return song.key.isEmpty ? nil : String(localized: "Tonart \(song.key)")
    }

    @ViewBuilder
    private func ccli(_ song: Song) -> some View {
        let parts: [String?] = [
            model.license.isEmpty ? nil : String(localized: "CCLI-Lizenz \(model.license)"),
            song.ccli.isEmpty ? nil : String(localized: "CCLI-Lied \(song.ccli)"),
            song.copyright.isEmpty ? nil : "© " + song.copyright.droppingPrefix("©").trimmingCharacters(in: .whitespaces)
        ]
        let notes = parts.compactMap { $0 }
        if !notes.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Hairline()
                ForEach(notes, id: \.self) { Text($0).font(.system(size: 12)).foregroundStyle(Palette.textSecondary) }
            }
            .padding(.top, 28)
        }
    }

    /// Floating control pill at the bottom of the song page.
    private func controls(keyLabel: String) -> some View {
        HStack(spacing: 2) {
            controlButton("minus", label: "Halbton tiefer") { steps = SongbookLogic.step(steps, by: -1) }
            // The key; while transposed a tap goes back to the original key
            Button { steps = 0 } label: {
                Text(keyLabel)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(steps != 0 ? Palette.primary : Palette.text)
                    .frame(width: 46, height: 40)
            }
            .disabled(steps == 0)
            .accessibilityLabel(steps != 0 ? "Zurück zur Originaltonart" : "Originaltonart")
            controlButton("plus", label: "Halbton höher") { steps = SongbookLogic.step(steps, by: 1) }
            Rectangle().fill(Palette.borderLight).frame(width: 1, height: 24).padding(.horizontal, 4)
            Button { chords.toggle() } label: {
                Image(systemName: "music.note")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(chords ? Palette.primary : Palette.textSecondary.opacity(0.6))
                    .frame(width: 40, height: 40)
            }
            .accessibilityLabel("Akkorde anzeigen")
            .accessibilityAddTraits(chords ? .isSelected : [])
            Button { size = max(-2, size - 1) } label: {
                Text("A−").font(.system(size: 14, weight: .semibold)).foregroundStyle(Palette.text).frame(width: 36, height: 40)
            }
            .disabled(size <= -2)
            .accessibilityLabel("Kleinere Schrift")
            Button { size = min(5, size + 1) } label: {
                Text("A+").font(.system(size: 17, weight: .bold)).foregroundStyle(Palette.text).frame(width: 36, height: 40)
            }
            .disabled(size >= 5)
            .accessibilityLabel("Größere Schrift")
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Palette.borderLight, lineWidth: 1))
        .shadow(color: .black.opacity(0.14), radius: 12, y: 4)
    }

    private func controlButton(_ icon: String, label: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 16, weight: .semibold)).foregroundStyle(Palette.text).frame(width: 40, height: 40)
        }
        .accessibilityLabel(label)
    }
}

/// One line of a song like the web app (song-line / song-seg): chords sit above the syllable they stand in front of,
/// a line wraps between words, sections are small capitals in the brand colour, notes in italics.
struct SongLineView: View {
    let line: SongLine
    let fontSize: CGFloat
    var first = false

    var body: some View {
        switch line {
        case .gap:
            Color.clear.frame(height: fontSize * 0.9)
        case .section(let text, let label):
            let title = text.trimmingCharacters(in: .whitespaces).isEmpty ? Self.sectionLabel(label) : text
            Text(title.uppercased())
                .font(.system(size: fontSize * 0.78, weight: .bold))
                .tracking(fontSize * 0.78 * 0.08)
                .foregroundStyle(Palette.primary)
                .padding(.top, first ? 0 : 18)
                .padding(.bottom, 6)
                .accessibilityAddTraits(.isHeader)
        case .note(let text):
            Text(text).font(.system(size: fontSize)).italic().foregroundStyle(Palette.textSecondary)
                .lineSpacing(fontSize * 0.25)
                .padding(.vertical, 4)
        case .text(let text):
            Text(text).font(.system(size: fontSize)).foregroundStyle(Palette.text)
                .lineSpacing(fontSize * 0.25)
        case .chords(let words):
            let only = SongbookLogic.chordsOnly(words)
            FlowLayout(spacing: only ? fontSize * 0.75 : fontSize * 0.3) {
                ForEach(Array(words.enumerated()), id: \.offset) { _, word in
                    wordView(word, chordsOnly: only)
                }
            }
            .padding(.top, fontSize * 0.15)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(words.flatMap { $0 }.map(\.text).joined()))
        }
    }

    private func wordView(_ word: [SongSegment], chordsOnly: Bool) -> some View {
        HStack(alignment: .bottom, spacing: 0) {
            ForEach(Array(word.enumerated()), id: \.offset) { index, segment in
                VStack(alignment: .leading, spacing: 0) {
                    // A space keeps the chord row where a syllable has no chord of its own
                    Text(segment.chord ?? " ")
                        .font(.system(size: fontSize * 0.86, weight: .bold))
                        .foregroundStyle(Palette.primary)
                        .lineLimit(1)
                        .fixedSize()
                        .padding(.trailing, segment.chord != nil ? fontSize * 0.3 : 0)
                    if !chordsOnly {
                        // Trailing spaces end a word; the gap between words comes from the layout
                        Text(index == word.count - 1 ? String(segment.text.reversed().drop(while: \.isWhitespace).reversed()) : segment.text)
                            .font(.system(size: fontSize))
                            .foregroundStyle(Palette.text)
                            .lineLimit(1)
                            .fixedSize()
                    }
                }
            }
        }
    }

    /// Labels of ChordPro sections without their own text ({start_of_chorus} …).
    static func sectionLabel(_ label: String?) -> String {
        switch label {
        case "chorus": return String(localized: "Refrain")
        case "verse": return String(localized: "Strophe")
        case "bridge": return String(localized: "Bridge")
        case "tab": return String(localized: "Tab")
        default: return ""
        }
    }
}
