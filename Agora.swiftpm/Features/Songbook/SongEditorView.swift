import SwiftUI

/// Editor of the web app: title, songwriter and key, the text with chords and a live preview, CCLI number and
/// copyright. Capo and tempo are no longer edited; a song keeps the values it already has. Leaving with changes
/// asks first; deleting asks too.
struct SongEditorView: View {
    let model: SongbookModel
    let song: Song?
    /// After deleting: the song page that opened the editor closes too.
    var onDeleted: (() -> Void)?
    @Environment(ToastCenter.self) private var toasts
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var artist = ""
    @State private var key = ""
    @State private var content = ""
    @State private var ccli = ""
    @State private var copyright = ""
    @State private var prepared = false
    @State private var confirmDiscard = false
    @State private var confirmDelete = false
    @State private var busy = false
    @State private var error: String?

    private var original: [String] {
        [song?.title ?? "", song?.artist ?? "", song?.key ?? "", song?.content ?? "", song?.ccli ?? "", song?.copyright ?? ""]
    }

    private var changed: Bool { prepared && [title, artist, key, content, ccli, copyright] != original }

    var body: some View {
        let preview = SongbookLogic.parse(content, steps: 0, declaredKey: key, chords: true)
        NavigationStack {
            Form {
                Section("Lied") {
                    TextField("Titel", text: $title)
                    TextField("Autor(en)", text: $artist)
                    TextField("Tonart, z. B. G", text: $key)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .onChange(of: key) { _, value in if value.count > 4 { key = String(value.prefix(4)) } }
                }
                Section {
                    TextEditor(text: $content)
                        .font(.system(size: 14, design: .monospaced))
                        .frame(minHeight: 220)
                        .textInputAutocapitalization(.sentences)
                } header: {
                    Text("Text & Akkorde")
                } footer: {
                    Text("Akkorde in eckigen Klammern direkt vor die Silbe: [G]Großer [D]Gott. Abschnitte mit # am Zeilenanfang, z. B. # Refrain. Leere Zeile = neuer Absatz.")
                }
                Section("Vorschau") {
                    if preview.isEmpty {
                        Text("Hier erscheint das Lied, wie es angezeigt wird.").foregroundStyle(Palette.textSecondary)
                    } else {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(Array(preview.enumerated()), id: \.offset) { index, line in
                                SongLineView(line: line, fontSize: 15, first: index == 0)
                            }
                        }
                        .padding(.vertical, 6)
                    }
                }
                Section {
                    TextField("CCLI-Liednummer", text: $ccli)
                        .keyboardType(.numberPad)
                        .onChange(of: ccli) { _, value in
                            let digits = String(value.filter(\.isNumber).prefix(12))
                            if digits != value { ccli = digits }
                        }
                    TextField("Copyright", text: $copyright)
                } header: {
                    Text("Rechte")
                } footer: {
                    // A CCLI song number only counts together with the church's licence number
                    if model.license.isEmpty {
                        Text("Die CCLI-Lizenznummer der Gemeinde fehlt noch – ein Admin trägt sie in den Systemeinstellungen ein. Sie wird bei jedem Lied angezeigt.")
                    }
                }
                if let error {
                    Section { Text(error).foregroundStyle(Palette.danger) }
                }
                if song != nil {
                    Section {
                        Button("Lied löschen", role: .destructive) { confirmDelete = true }
                    }
                }
            }
            .navigationTitle(song == nil ? "Neues Lied" : "Lied bearbeiten")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { if changed { confirmDiscard = true } else { dismiss() } }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if busy {
                        ProgressView()
                    } else {
                        Button("Speichern", action: save).bold()
                            .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty || content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
            .interactiveDismissDisabled(changed || busy)
            .confirmationDialog("Änderungen verwerfen?", isPresented: $confirmDiscard, titleVisibility: .visible) {
                Button("Verwerfen", role: .destructive) { dismiss() }
            } message: {
                Text("Deine Änderungen an diesem Lied gehen verloren.")
            }
            .confirmationDialog("Lied endgültig löschen?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Löschen", role: .destructive, action: delete)
            }
        }
        .onAppear {
            guard !prepared else { return }
            title = song?.title ?? ""
            artist = song?.artist ?? ""
            key = song?.key ?? ""
            content = song?.content ?? ""
            ccli = song?.ccli ?? ""
            copyright = song?.copyright ?? ""
            prepared = true
        }
    }

    private func save() {
        let input = SongInput(title: title, artist: artist, key: key, ccli: ccli, copyright: copyright, content: content,
                              capo: song?.capo, tempo: song?.tempo)
        let id = song?.id
        run(success: String(localized: "Lied gespeichert")) {
            let saved = try await store.repository.saveSong(id: id, input)
            model.upsert(saved)
        } done: {
            dismiss()
        }
    }

    private func delete() {
        guard let id = song?.id else { return }
        run(success: String(localized: "Lied gelöscht")) {
            try await store.repository.deleteSong(id: id)
            model.remove(id)
        } done: {
            dismiss()
            onDeleted?()
        }
    }

    private func run(success: String, _ work: @escaping () async throws -> Void, done: @escaping () -> Void) {
        guard !busy else { return }
        busy = true
        error = nil
        Task {
            defer { busy = false }
            do {
                try await work()
                toasts.show(success)
                done()
            } catch is CancellationError {
            } catch {
                self.error = APIError.text(error)
            }
        }
    }
}
