import SwiftUI

/// The songbook in memory; loaded when the page opens, kept up to date after saving or deleting.
@MainActor
@Observable
final class SongbookModel {
    /// A song with its prepared search text (title, writers, CCLI, lyrics; lower case, no accents).
    struct Entry: Identifiable {
        let song: Song
        let search: String
        var id: String { song.id }

        init(_ song: Song) {
            self.song = song
            search = SongbookLogic.searchText(song)
        }
    }

    private(set) var loaded = false
    private(set) var loading = false
    private(set) var error: String?
    private(set) var entries: [Entry] = []
    private(set) var license = ""
    private(set) var canManage = false

    func load(_ store: AppStore) async {
        guard !loading else { return }
        loading = true
        defer { loading = false }
        do {
            let book = try await store.repository.songbook()
            entries = book.songs.map(Entry.init)
            license = book.ccliLicense.trimmingCharacters(in: .whitespaces)
            canManage = book.canManage
            loaded = true
            error = nil
        } catch is CancellationError {
        } catch {
            self.error = APIError.text(error)
        }
    }

    func song(_ id: String?) -> Song? { entries.first { $0.song.id == id }?.song }

    func upsert(_ song: Song) {
        entries = (entries.filter { $0.song.id != song.id } + [Entry(song)])
            .sorted { $0.song.title.localizedStandardCompare($1.song.title) == .orderedAscending }
    }

    func remove(_ id: String) { entries.removeAll { $0.song.id == id } }
}

/// Which song the editor opens; `song` nil is a new one.
struct SongEditTarget: Identifiable {
    let song: Song?
    var id: String { song?.id ?? "new" }
}

/// The songbook of the web app (Extras → Liederbuch): searchable alphabetical list, a song page with chords,
/// transposing and text size, and the editor for members who may manage the songbook.
struct SongbookView: View {
    @Environment(AppStore.self) private var store
    @State private var model = SongbookModel()
    @State private var query = ""
    @State private var openSong: String?
    @State private var editing: SongEditTarget?

    var body: some View {
        let needle = SongbookLogic.normalizeSearch(query.trimmingCharacters(in: .whitespaces))
        let list = needle.isEmpty ? model.entries : model.entries.filter { $0.search.contains(needle) }
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                SearchField(placeholder: "Titel, Autor, Liedtext oder CCLI-Nummer suchen…", text: $query)
                if !model.loaded, let error = model.error {
                    VStack(spacing: 12) {
                        EmptyState(systemImage: "music.note", title: LocalizedStringKey(error))
                        Button("Erneut versuchen") { Task { await model.load(store) } }
                            .buttonStyle(.agoraSecondary(small: true, fullWidth: false))
                    }
                    .frame(maxWidth: .infinity)
                } else if !model.loaded {
                    ProgressView().tint(Palette.primary).frame(maxWidth: .infinity).padding(.vertical, 60)
                } else if list.isEmpty {
                    EmptyState(systemImage: "music.note",
                               title: needle.isEmpty ? "Noch keine Lieder im Liederbuch" : "Kein Lied gefunden",
                               message: model.canManage && needle.isEmpty ? "Mit dem Plus oben rechts legst du das erste Lied an." : nil)
                } else {
                    songList(list, letters: needle.isEmpty)
                    licenseNote
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 32)
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Palette.background.ignoresSafeArea())
        .navigationTitle("Liederbuch")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if model.canManage {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { editing = SongEditTarget(song: nil) } label: { Image(systemName: "plus") }
                        .accessibilityLabel("Lied hinzufügen")
                }
            }
        }
        .refreshable { await model.load(store) }
        .task { if !model.loaded { await model.load(store) } }
        .navigationDestination(item: $openSong) { id in
            SongPageView(model: model, songId: id)
        }
        .sheet(item: $editing) { target in
            SongEditorView(model: model, song: target.song)
        }
    }

    /// Alphabetical list in one card, a letter above each new initial (only without a search).
    private struct ListRow: Identifiable {
        let id: String
        var letter: String?
        var song: Song?
    }

    private func songList(_ list: [SongbookModel.Entry], letters: Bool) -> some View {
        var rows: [ListRow] = []
        var current: String?
        for entry in list {
            let initial = entry.song.title.first.map { String($0).uppercased() } ?? "#"
            if letters && initial != current { rows.append(ListRow(id: "letter-\(initial)-\(rows.count)", letter: initial)) }
            current = initial
            rows.append(ListRow(id: "song-\(entry.song.id)", song: entry.song))
        }
        return VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                if index > 0 { Hairline() }
                if let letter = row.letter {
                    Text(letter)
                        .font(.system(size: 12, weight: .bold))
                        .tracking(1)
                        .foregroundStyle(Palette.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)
                        .padding(.top, 9)
                        .padding(.bottom, 4)
                        .background(Palette.surfaceAlt)
                        .accessibilityAddTraits(.isHeader)
                } else if let song = row.song {
                    Button { openSong = song.id } label: { SongRow(song: song) }
                        .buttonStyle(.plain)
                }
            }
        }
        .background(Palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: Radius.large, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.large, style: .continuous).strokeBorder(Palette.borderLight, lineWidth: 1))
        .shadow(color: Palette.shadow, radius: 4, y: 1)
    }

    @ViewBuilder
    private var licenseNote: some View {
        if !model.license.isEmpty {
            Text("CCLI-Lizenz \(model.license)")
                .font(.system(size: 12)).foregroundStyle(Palette.textSecondary)
                .frame(maxWidth: .infinity)
        } else if model.canManage {
            Text("Die CCLI-Lizenznummer der Gemeinde fehlt noch – ein Admin trägt sie in den Systemeinstellungen ein. Sie wird bei jedem Lied angezeigt.")
                .font(.system(size: 12)).foregroundStyle(Palette.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 8)
        }
    }
}

private struct SongRow: View {
    let song: Song

    var body: some View {
        let keyLabel = song.key.isEmpty ? "" : String(localized: "Tonart \(song.key)")
        let meta = [song.artist, keyLabel].filter { !$0.isEmpty }.joined(separator: " · ")
        HStack(spacing: 12) {
            IconTile(systemImage: "music.note", color: Palette.primary, size: 38)
            VStack(alignment: .leading, spacing: 2) {
                Text(song.title).font(.system(size: 15, weight: .semibold)).foregroundStyle(Palette.text).lineLimit(1)
                if !meta.isEmpty {
                    Text(meta).font(.system(size: 12.5)).foregroundStyle(Palette.textSecondary).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.system(size: 12, weight: .bold)).foregroundStyle(Palette.textSecondary.opacity(0.6))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}
