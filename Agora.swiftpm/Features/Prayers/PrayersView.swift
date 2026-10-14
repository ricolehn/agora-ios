import SwiftUI

enum Prayers {
    /// Rose of the prayer page (web: #e11d48 in .polls-note and the empty state).
    static let rose = Color(hex: 0xE11D48)
    static let maxText = 1000

    /// "vor 2 Stunden", "gestern"; older than a week as a date (web: timeAgo).
    static func timeAgo(_ millis: Int64, now: Date = Date()) -> String {
        let date = Date(timeIntervalSince1970: Double(millis) / 1000)
        if now.timeIntervalSince(date) > 7 * 24 * 3600 { return day(millis) }
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Formats.locale
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: now)
    }

    /// "3. Okt."
    static func day(_ millis: Int64) -> String {
        let formatter = DateFormatter()
        formatter.locale = Formats.locale
        formatter.setLocalizedDateFormatFromTemplate("dMMM")
        return formatter.string(from: Date(timeIntervalSince1970: Double(millis) / 1000))
    }

    static func name(_ prayer: Prayer) -> String {
        guard let author = prayer.author else { return String(localized: "Anonym") }
        return author.name.trimmingCharacters(in: .whitespaces).isEmpty ? String(localized: "Mitglied") : author.name
    }
}

/// The list of the prayer page; reloaded when the page opens and after every own change.
@MainActor
@Observable
final class PrayersModel {
    private(set) var prayers: [Prayer] = []
    private(set) var loaded = false
    /// Only shown while nothing has been loaded yet; later failures go to the toast of the action.
    private(set) var error: String?

    func load(_ store: AppStore) async {
        do {
            prayers = try await store.repository.prayers().prayers
            loaded = true
            error = nil
        } catch is CancellationError {
        } catch {
            if !loaded { self.error = APIError.text(error) }
        }
    }

    func share(_ store: AppStore, text: String, duration: PrayerDuration, anonymous: Bool) async throws {
        try await store.repository.sharePrayer(text: text, duration: duration, anonymous: anonymous)
        prayers = try await store.repository.prayers().prayers
    }

    func extend(_ store: AppStore, id: String) async throws {
        let updated = try await store.repository.extendPrayer(id: id)
        prayers = prayers.map { $0.id == updated.id ? updated : $0 }
    }

    func delete(_ store: AppStore, id: String) async throws {
        try await store.repository.deletePrayer(id: id)
        prayers.removeAll { $0.id == id }
    }
}

/// Prayer requests (Extras) like the web app v3.1: a calm intro, All / Mine, every request as its own quiet card
/// (the words first, who and when small above, long ones folded to four lines), "+" to share one. Own requests
/// (and every request for moderators) open their options with a tap.
struct PrayersView: View {
    @Environment(AppStore.self) private var store
    @State private var model = PrayersModel()
    @State private var mineOnly = false
    @State private var sharing = false
    @State private var options: Prayer?

    var body: some View {
        let list = model.prayers.filter { mineOnly ? $0.isMine : !$0.expired }
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                introNote
                PillTabs(items: [.init(value: false, title: "Alle"), .init(value: true, title: "Meine")], selection: $mineOnly)
                    .frame(maxWidth: 240)
                    .padding(.vertical, 4)
                if !model.loaded, let error = model.error {
                    VStack(spacing: 12) {
                        EmptyState(systemImage: "heart", title: LocalizedStringKey(error))
                        Button("Erneut versuchen") { Task { await model.load(store) } }
                            .buttonStyle(.agoraSecondary(small: true, fullWidth: false))
                    }
                    .frame(maxWidth: .infinity)
                } else if !model.loaded {
                    ProgressView().tint(Palette.primary).frame(maxWidth: .infinity).padding(.vertical, 60)
                } else if list.isEmpty {
                    emptyCard
                } else {
                    ForEach(list) { prayer in
                        PrayerCard(prayer: prayer) { options = prayer }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 96)
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
        }
        .background(Palette.background.ignoresSafeArea())
        .navigationTitle("Gebetsanliegen")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await model.load(store) }
        .task { await model.load(store) }
        .overlay(alignment: .bottomTrailing) {
            Button { sharing = true } label: {
                Image(systemName: "plus")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 54, height: 54)
                    .background(Palette.brand, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .shadow(color: .black.opacity(0.25), radius: 10, y: 5)
            }
            .accessibilityLabel("Gebetsanliegen teilen")
            .padding(.trailing, 18)
            .padding(.bottom, 16)
        }
        .sheet(isPresented: $sharing) {
            SharePrayerSheet(model: model) { mineOnly = false }
                .presentationDetents([.large])
        }
        .sheet(item: $options) { prayer in
            PrayerOptionsSheet(model: model, prayer: prayer)
                .presentationDetents([.medium, .large])
        }
    }

    /// The rose intro card of the web app (`#prayers .polls-note`).
    private var introNote: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "heart").font(.system(size: 15, weight: .semibold)).foregroundStyle(Prayers.rose.opacity(0.85)).padding(.top, 1)
            Text("Teile, was dir auf dem Herzen liegt – mit Namen oder anonym. Wenn es sich erledigt hat, entfernst du es einfach.")
                .font(.system(size: 14)).foregroundStyle(Palette.textSecondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Prayers.rose.opacity(0.05), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Prayers.rose.opacity(0.14), lineWidth: 1))
    }

    private var emptyCard: some View {
        VStack(spacing: 4) {
            Image(systemName: "heart")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(Prayers.rose)
                .frame(width: 52, height: 52)
                .background(Prayers.rose.opacity(0.10), in: Circle())
                .padding(.bottom, 8)
            Text(mineOnly ? "Du hast noch kein Anliegen geteilt" : "Gerade gibt es keine Gebetsanliegen")
                .font(.system(size: 16, weight: .semibold)).foregroundStyle(Palette.text).multilineTextAlignment(.center)
            Text("Teile ein Anliegen mit dem Plus unten rechts.").font(.system(size: 14)).foregroundStyle(Palette.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 36)
        .card(padding: nil)
        .padding(.top, 4)
    }
}

/// One request: picture and name, when; the words below, folded to four lines with "Weiterlesen" in place.
private struct PrayerCard: View {
    let prayer: Prayer
    let onOptions: () -> Void
    @State private var expanded = false
    @State private var fullHeight: CGFloat = 0
    @State private var foldedHeight: CGFloat = 0

    var body: some View {
        let editable = prayer.isMine || prayer.canDelete
        let dim = prayer.expired ? 0.6 : 1.0
        let until: String? = !prayer.isMine ? nil
            : (prayer.expired ? String(localized: "Abgelaufen") : String(localized: "bis \(Prayers.day(prayer.expiresAt))"))
        let meta = [Prayers.timeAgo(prayer.createdAt), until].compactMap { $0 }.joined(separator: " · ")
        let overflows = fullHeight > foldedHeight + 1
        HStack(alignment: .top, spacing: 12) {
            if let author = prayer.author {
                Avatar(userId: author.uid.isEmpty ? nil : author.uid, name: Prayers.name(prayer), size: 36)
            } else {
                Image(systemName: "eye.slash")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Palette.textSecondary)
                    .frame(width: 36, height: 36)
                    .background(Palette.surfaceAlt, in: Circle())
                    .accessibilityLabel("Anonym")
            }
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 0) {
                    Text(Prayers.name(prayer)).font(.system(size: 14, weight: .semibold)).foregroundStyle(Palette.text.opacity(dim)).lineLimit(1)
                    Text(" · \(meta)").font(.system(size: 12.5)).foregroundStyle(Palette.textSecondary.opacity(dim)).lineLimit(1)
                }
                Text(prayer.text)
                    .font(.system(size: 15))
                    .foregroundStyle(Palette.text.opacity(dim))
                    .lineLimit(expanded ? nil : 4)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(GeometryReader { proxy in
                        Color.clear.onChange(of: proxy.size.height, initial: true) { _, height in foldedHeight = height }
                    })
                    // The whole text measured too (also after rotation), to know whether "Weiterlesen" is needed
                    .background(alignment: .topLeading) {
                        Text(prayer.text).font(.system(size: 15)).fixedSize(horizontal: false, vertical: true).hidden()
                            .background(GeometryReader { proxy in
                                Color.clear.onChange(of: proxy.size.height, initial: true) { _, height in fullHeight = height }
                            })
                    }
                if overflows || expanded {
                    Button {
                        withAnimation(.snappy) { expanded.toggle() }
                    } label: {
                        Text(expanded ? "Weniger anzeigen" : "Weiterlesen").font(.system(size: 14, weight: .semibold)).foregroundStyle(Palette.primary)
                    }
                    .buttonStyle(.plain)
                }
            }
            if editable {
                Image(systemName: "ellipsis").font(.system(size: 16, weight: .semibold)).foregroundStyle(Palette.textSecondary)
                    .padding(.top, 4)
                    .accessibilityHidden(true)
            }
        }
        .padding(.leading, 14)
        .padding(.trailing, 12)
        .padding(.top, 14)
        .padding(.bottom, 16)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).strokeBorder(Palette.borderLight, lineWidth: 1))
        .shadow(color: Palette.shadow, radius: 4, y: 1)
        .contentShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .onTapGesture { if editable { onOptions() } }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(editable ? .isButton : [])
        .accessibilityHint(editable ? "Optionen" : "")
    }
}

/// Share a request (web: #prayer-edit-modal): text with counter, how long it is shown, anonymous or not.
private struct SharePrayerSheet: View {
    let model: PrayersModel
    let onShared: () -> Void
    @Environment(AppStore.self) private var store
    @Environment(ToastCenter.self) private var toasts
    @Environment(\.dismiss) private var dismiss
    @State private var action = FormAction()
    @State private var text = ""
    @State private var duration = PrayerDuration.month
    @State private var anonymous = false

    var body: some View {
        FormSheet(title: "Gebetsanliegen teilen", confirm: "Teilen", canConfirm: text.trimmingCharacters(in: .whitespacesAndNewlines).count >= 3,
                  busy: action.busy, error: action.error, onConfirm: share) {
            Section {
                TextField("Wofür dürfen wir beten?", text: $text, axis: .vertical)
                    .lineLimit(5...12)
                    .onChange(of: text) { _, value in if value.count > Prayers.maxText { text = String(value.prefix(Prayers.maxText)) } }
            } header: {
                Text("Dein Anliegen")
            } footer: {
                Text("\(text.count) / \(Prayers.maxText)").frame(maxWidth: .infinity, alignment: .trailing)
            }
            Section("Sichtbar für") {
                Picker("Sichtbar für", selection: $duration) {
                    ForEach(PrayerDuration.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            Section {
                Toggle(isOn: $anonymous) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Anonym teilen")
                        Text("Niemand sieht, von wem es ist – auch die Leitung nicht.").font(.footnote).foregroundStyle(Palette.textSecondary)
                    }
                }
            }
        }
    }

    private func share() {
        let words = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let chosen = duration
        let hidden = anonymous
        action.run(toasts: toasts, success: String(localized: "Dein Gebetsanliegen wurde geteilt"), dismiss: dismiss) {
            try await model.share(store, text: words, duration: chosen, anonymous: hidden)
            onShared()
        }
    }
}

/// The options of a request (web: openPrayerOptions): the owner extends it by a month or removes it when it is
/// done; a moderator removes it after a confirmation.
private struct PrayerOptionsSheet: View {
    let model: PrayersModel
    let prayer: Prayer
    @Environment(AppStore.self) private var store
    @Environment(ToastCenter.self) private var toasts
    @Environment(\.dismiss) private var dismiss
    @State private var runner = ActionRunner()
    @State private var confirming = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(subtitle).font(.system(size: 13.5)).foregroundStyle(Palette.textSecondary)
                    Text(prayer.text).font(.system(size: 16)).foregroundStyle(Palette.text).textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                    if prayer.isMine {
                        HStack(spacing: 10) {
                            Button {
                                runner.run(toasts, success: String(localized: "Wird einen weiteren Monat angezeigt")) {
                                    try await model.extend(store, id: prayer.id)
                                } done: { dismiss() }
                            } label: { Label("Einen Monat länger", systemImage: "clock") }
                                .buttonStyle(.agoraSecondary)
                            Button {
                                runner.run(toasts, success: String(localized: "Entfernt – danke fürs Teilen")) {
                                    try await model.delete(store, id: prayer.id)
                                } done: { dismiss() }
                            } label: { BusyLabel(title: "Fertig – entfernen", systemImage: "checkmark", busy: runner.busy) }
                                .buttonStyle(.agoraPrimary)
                        }
                        .disabled(runner.busy)
                    } else {
                        Button { confirming = true } label: { Label("Entfernen", systemImage: "trash") }
                            .buttonStyle(.agoraDanger)
                            .disabled(runner.busy)
                    }
                }
                .padding(20)
            }
            .navigationTitle(prayer.isMine ? String(localized: "Dein Gebetsanliegen") : Prayers.name(prayer))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Schließen") { dismiss() } } }
            .confirmationDialog("Dieses Gebetsanliegen für alle entfernen?", isPresented: $confirming, titleVisibility: .visible) {
                Button("Entfernen", role: .destructive) {
                    runner.run(toasts, success: String(localized: "Gebetsanliegen gelöscht")) {
                        try await model.delete(store, id: prayer.id)
                    } done: { dismiss() }
                }
            }
        }
    }

    private var subtitle: String {
        if !prayer.isMine { return Prayers.timeAgo(prayer.createdAt) }
        if prayer.expired { return String(localized: "Wird nicht mehr angezeigt – verlängere es, um es wieder zu zeigen") }
        return String(localized: "Sichtbar bis \(Prayers.day(prayer.expiresAt))")
    }
}
