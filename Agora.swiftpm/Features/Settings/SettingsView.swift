import SwiftUI
import PhotosUI

/// Settings like the web and Android: a menu of sub-pages (native grouped list); the registration code stays on
/// the main page.
struct SettingsView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.horizontalSizeClass) private var sizeClass
    @AppStorage(AppInfo.themeKey) private var theme = ThemeChoice.system.rawValue
    @State private var confirmLogout = false

    var body: some View {
        List {
            if let user = store.user {
                Section {
                    NavigationLink { ProfileSettingsPage() } label: {
                        HStack(spacing: 14) {
                            Avatar(userId: user.userId, name: user.fullName, size: 52, ring: user.ring)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(user.fullName).font(.system(size: 17, weight: .bold)).foregroundStyle(Palette.text)
                                Text(user.email).font(.subheadline).foregroundStyle(Palette.textSecondary).lineLimit(1)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
                if user.managesRegistrationCode { InviteCodeSection() }
                Section("Allgemein") {
                    NavigationLink { NotificationSettingsPage() } label: {
                        SettingsRow(title: "Benachrichtigungen", subtitle: Self.summary(user.notificationPrefs), systemImage: "bell", color: Color(hex: 0xF59E0B))
                    }
                    NavigationLink { AppearanceSettingsPage() } label: {
                        SettingsRow(title: "Darstellung & Sprache", subtitle: (ThemeChoice(rawValue: theme) ?? .system).name,
                                    systemImage: "paintpalette", color: Color(hex: 0x8B5CF6))
                    }
                    NavigationLink { PasswordSettingsPage() } label: {
                        SettingsRow(title: "Passwort ändern", subtitle: String(localized: "Neues Passwort festlegen"), systemImage: "key", color: Color(hex: 0x64748B))
                    }
                }
                if user.isAdmin {
                    Section("Verwaltung") {
                        NavigationLink { FeeSettingsPage() } label: {
                            SettingsRow(title: "Monatliche Beiträge", subtitle: String(localized: "Beitrag je Mitgliedsstatus"), systemImage: "eurosign", color: Color(hex: 0x10B981))
                        }
                    }
                }
                Section {
                    NavigationLink { CalendarSettingsPage() } label: {
                        SettingsRow(title: "Kalender-Abonnement", subtitle: String(localized: "Termine in deiner Kalender-App"), systemImage: "calendar", color: Color(hex: 0x0891B2))
                    }
                    NavigationLink { AccountSettingsPage() } label: {
                        SettingsRow(title: "Datenschutz & Konto", subtitle: String(localized: "Datenschutz, Browser, Konto löschen"), systemImage: "person.crop.circle", color: Color(hex: 0x0EA5E9))
                    }
                    Button(role: .destructive) { confirmLogout = true } label: {
                        Label("Abmelden", systemImage: "rectangle.portrait.and.arrow.right").foregroundStyle(Palette.danger)
                    }
                } header: {
                    Text("Kalender, Datenschutz & Konto")
                } footer: {
                    Text("Agora iOS \(AppInfo.version)").frame(maxWidth: .infinity).padding(.top, 12)
                }
            }
        }
        .settingsPage(regular: sizeClass == .regular)
        .navigationTitle("Einstellungen")
        .navigationBarTitleDisplayMode(.large)
        .confirmationDialog("Abmelden?", isPresented: $confirmLogout, titleVisibility: .visible) {
            Button("Abmelden", role: .destructive) { Task { await store.logout() } }
        }
    }

    private static func summary(_ prefs: NotificationPrefs) -> String {
        switch (prefs.channels.push, prefs.channels.email) {
        case (true, true): return String(localized: "Push und E-Mail")
        case (true, false): return String(localized: "Nur Push")
        case (false, true): return String(localized: "Nur E-Mail")
        default: return String(localized: "Aus")
        }
    }

    static func amountText(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(2)).locale(Locale(identifier: "de_DE")))
    }
}

private extension View {
    /// Grouped list on the app background; on iPad a readable column in the middle.
    func settingsPage(regular: Bool) -> some View {
        self
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .frame(maxWidth: regular ? 760 : .infinity)
            .frame(maxWidth: .infinity)
            .background(Palette.background.ignoresSafeArea())
    }
}

/// Menu row: coloured tile like the system settings, title and a short summary.
private struct SettingsRow: View {
    let title: LocalizedStringKey
    var subtitle: String?
    let systemImage: String
    let color: Color

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(color, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).foregroundStyle(Palette.text)
                if let subtitle {
                    Text(subtitle).font(.caption).foregroundStyle(Palette.textSecondary).lineLimit(2)
                }
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Registration code (main page)

private struct InviteCodeSection: View {
    @Environment(AppStore.self) private var store
    @Environment(ToastCenter.self) private var toasts
    @State private var runner = ActionRunner()
    @State private var inviteCode: String?

    var body: some View {
        Section {
            VStack(spacing: 6) {
                CapsLabel("Aktueller Code")
                Text(inviteCode ?? "–")
                    .font(.system(size: 30, weight: .heavy, design: .monospaced))
                    .tracking(3)
                    .textSelection(.enabled)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            Button {
                UIPasteboard.general.string = inviteCode
                toasts.show(String(localized: "In die Zwischenablage kopiert"))
            } label: { Label("Kopieren", systemImage: "doc.on.doc") }
                .disabled(inviteCode == nil)
            Button(action: newInviteCode) { Label("Neuer Code", systemImage: "arrow.clockwise") }
                .disabled(runner.busy)
        } header: {
            Text("Registrierungscode")
        } footer: {
            Text("Mit diesem Code können sich neue Mitglieder registrieren.")
        }
        .task { inviteCode = await store.repository.inviteCode() }
    }

    private func newInviteCode() {
        let code = String(Int.random(in: 100_000...999_999))
        runner.run(toasts, success: String(localized: "Gespeichert")) {
            try await store.repository.setInviteCode(code)
            inviteCode = code
        }
    }
}

// MARK: - Profile

private struct ProfileSettingsPage: View {
    @Environment(AppStore.self) private var store
    @Environment(ToastCenter.self) private var toasts
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var photo: PhotosPickerItem?
    @State private var pictureRevision = 0
    @State private var uploading = false

    var body: some View {
        List {
            if let user = store.user {
                Section {
                    VStack(spacing: 10) {
                        Avatar(userId: user.userId, name: user.fullName, size: 96, ring: user.ring, revision: pictureRevision)
                        Text(user.fullName).font(.system(size: 20, weight: .bold)).foregroundStyle(Palette.text)
                        Text(user.email).font(.subheadline).foregroundStyle(Palette.textSecondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    PhotosPicker(selection: $photo, matching: .images) {
                        HStack {
                            Label("Bild hochladen", systemImage: "square.and.arrow.up")
                            if uploading { Spacer(); ProgressView() }
                        }
                    }
                    .disabled(uploading)
                } header: {
                    Text("Profilbild")
                } footer: {
                    Text("JPG, PNG, HEIC – wird quadratisch als 256×256 JPEG gespeichert.")
                }
            }
        }
        .settingsPage(regular: sizeClass == .regular)
        .navigationTitle("Profil")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: photo) { _, item in upload(item) }
    }

    private func upload(_ item: PhotosPickerItem?) {
        guard let item, let user = store.user else { return }
        uploading = true
        Task {
            defer {
                uploading = false
                photo = nil
            }
            do {
                guard let data = try await item.loadTransferable(type: Data.self),
                      let jpeg = ImageTools.jpeg(from: data, aspect: 1, maxWidth: 256, quality: 0.9) else {
                    throw APIError(status: 0, message: String(localized: "Das Bild konnte nicht gelesen werden."))
                }
                try await store.repository.uploadProfilePicture(jpeg: jpeg)
                store.api.clearHTTPCache()
                if let url = store.repository.profilePictureURL(user.userId) { ImagePipeline.shared.forget(url) }
                pictureRevision += 1
                toasts.show(String(localized: "Profilbild gespeichert"))
            } catch {
                toasts.error(error)
            }
        }
    }
}

// MARK: - Notifications

/// Kind of message with its icon and colour (same order and choice as the web settings).
private struct NotificationKindInfo: Identifiable {
    let key: String
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey
    let systemImage: String
    let color: Color
    var id: String { key }

    static let all: [NotificationKindInfo] = [
        .init(key: "duties", title: "Dienstanfragen", subtitle: "Anfragen für Dienste, Antworten darauf und Dienste deiner Gruppen",
              systemImage: "calendar.badge.checkmark", color: Color(hex: 0x6366F1)),
        .init(key: "events", title: "Neue Events & Termine", subtitle: "Neue Veranstaltungen und Termine der Gemeinde",
              systemImage: "calendar", color: Color(hex: 0x0891B2)),
        .init(key: "messages", title: "Nachrichten", subtitle: "Begleitungsanfragen und Mentoring-Nachrichten",
              systemImage: "bubble.left.and.bubble.right", color: Color(hex: 0x7C3AED)),
        .init(key: "requests", title: "Meine Anfragen", subtitle: "Wenn deine Zahlung, Auslage oder Statusänderung genehmigt oder abgelehnt wurde",
              systemImage: "doc.text", color: Color(hex: 0x10B981)),
        .init(key: "finances", title: "Anfragen an die Kasse", subtitle: "Neue Zahlungs-, Auslagen- und Statusanfragen von Mitgliedern",
              systemImage: "eurosign.circle", color: Color(hex: 0xD97706)),
        .init(key: "reports", title: "Gemeldete Inhalte", subtitle: "Gemeldete Chat-Nachrichten und KI-Antworten",
              systemImage: "flag", color: Color(hex: 0xEF4444))
    ]
}

/// Notifications like the web: push and e-mail as master switches, below them per channel which kinds arrive.
/// Without e-mail there is no e-mail tab; finance requests only for those who decide on them, reported content only
/// for admins.
private struct NotificationSettingsPage: View {
    @Environment(AppStore.self) private var store
    @Environment(ToastCenter.self) private var toasts
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var prefs: NotificationPrefs?
    @State private var channel = "push"
    @State private var saveTask: Task<Void, Never>?

    var body: some View {
        List {
            if let user = store.user, let prefs {
                Section {
                    channelToggle("Push", subtitle: String(localized: "Direkt aufs Gerät"), systemImage: "bell", isOn: prefs.channels.push) { $0.channels.push = $1 }
                    channelToggle("E-Mail", subtitle: String(localized: "An \(user.email)"), systemImage: "envelope", isOn: prefs.channels.email) { $0.channels.email = $1 }
                } header: {
                    Text("Wähle, worüber du benachrichtigt wirst und welche Nachrichten du bekommst.")
                        .textCase(nil)
                } footer: {
                    Text("Push-Benachrichtigungen kommen in der iOS-App noch nicht an; solange die App geöffnet ist, aktualisiert sie sich live.")
                }
                if !prefs.channels.push && !prefs.channels.email {
                    Section {
                        Text("Du bekommst keine Benachrichtigungen. Schalte oben Push oder E-Mail ein.")
                            .font(.subheadline)
                            .foregroundStyle(Palette.textSecondary)
                    }
                } else {
                    let tab = prefs.channels.push && prefs.channels.email ? channel : (prefs.channels.push ? "push" : "email")
                    Section {
                        if prefs.channels.push && prefs.channels.email {
                            Picker("Kanal", selection: $channel) {
                                Text("Push").tag("push")
                                Text("E-Mail").tag("email")
                            }
                            .pickerStyle(.segmented)
                            .listRowBackground(Color.clear)
                            .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 8, trailing: 0))
                        }
                        ForEach(kinds(user)) { kind in kindToggle(kind, tab: tab, prefs: prefs) }
                    } header: {
                        Text("Was möchtest du bekommen?")
                    }
                }
            }
        }
        .settingsPage(regular: sizeClass == .regular)
        .navigationTitle("Benachrichtigungen")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { if prefs == nil { prefs = store.user?.notificationPrefs } }
    }

    private func kinds(_ user: User) -> [NotificationKindInfo] {
        NotificationKindInfo.all.filter {
            ($0.key != "finances" || user.isAdmin || user.managesFinances) && ($0.key != "reports" || user.isAdmin)
        }
    }

    private func channelToggle(_ title: LocalizedStringKey, subtitle: String, systemImage: String, isOn: Bool,
                               change: @escaping (inout NotificationPrefs, Bool) -> Void) -> some View {
        Toggle(isOn: Binding(get: { isOn }, set: { on in update(change)(on) })) {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Palette.primary)
                    .frame(width: 30)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 16, weight: .semibold))
                    Text(subtitle).font(.caption).foregroundStyle(Palette.textSecondary).lineLimit(1)
                }
            }
        }
        .tint(Palette.secondary)
    }

    private func kindToggle(_ kind: NotificationKindInfo, tab: String, prefs: NotificationPrefs) -> some View {
        let value = tab == "email" ? prefs.email[kind.key] : prefs.push[kind.key]
        return Toggle(isOn: Binding(get: { value }, set: { on in
            update { next, value in
                if tab == "email" { next.email[kind.key] = value } else { next.push[kind.key] = value }
            }(on)
        })) {
            HStack(spacing: 12) {
                Image(systemName: kind.systemImage)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(kind.color)
                    .frame(width: 30, height: 30)
                    .background(kind.color.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(kind.title)
                    Text(kind.subtitle).font(.caption).foregroundStyle(Palette.textSecondary)
                }
            }
        }
        .tint(Palette.secondary)
    }

    /// Applies a change right away and saves it shortly after (several taps in a row become one request).
    private func update(_ change: @escaping (inout NotificationPrefs, Bool) -> Void) -> (Bool) -> Void {
        { value in
            guard var next = prefs, let user = store.user else { return }
            change(&next, value)
            prefs = next
            let snapshot = next
            saveTask?.cancel()
            saveTask = Task {
                try? await Task.sleep(nanoseconds: 400_000_000)
                guard !Task.isCancelled else { return }
                do {
                    try await store.repository.saveNotificationSettings(uid: user.userId, snapshot)
                    try await store.reloadUser()
                } catch is CancellationError {
                } catch {
                    toasts.error(error)
                }
            }
        }
    }
}

// MARK: - Appearance

private struct AppearanceSettingsPage: View {
    @Environment(\.openURL) private var openURL
    @Environment(\.horizontalSizeClass) private var sizeClass
    @AppStorage(AppInfo.themeKey) private var theme = ThemeChoice.system.rawValue

    var body: some View {
        List {
            Section("Farbschema") {
                Picker("Farbschema", selection: $theme) {
                    ForEach(ThemeChoice.allCases) { Text($0.label).tag($0.rawValue) }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            }
            Section {
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                } label: {
                    LabeledContent("Sprache / Language") { Image(systemName: "arrow.up.forward.app").foregroundStyle(Palette.textSecondary) }
                }
                .foregroundStyle(Palette.text)
            } footer: {
                Text("Die App folgt der Sprache deines Geräts. Du kannst sie in den iOS-Einstellungen für Agora ändern.")
            }
        }
        .settingsPage(regular: sizeClass == .regular)
        .navigationTitle("Darstellung & Sprache")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Password

private struct PasswordSettingsPage: View {
    @Environment(AppStore.self) private var store
    @Environment(ToastCenter.self) private var toasts
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var runner = ActionRunner()
    @State private var oldPassword = ""
    @State private var newPassword = ""

    var body: some View {
        List {
            Section {
                SecureField("Altes Passwort", text: $oldPassword).textContentType(.password)
                SecureField("Neues Passwort (min. 6)", text: $newPassword).textContentType(.newPassword)
            } footer: {
                Text("Danach meldest du dich mit dem neuen Passwort wieder an.")
            }
            Section {
                Button(action: changePassword) {
                    HStack {
                        Spacer()
                        if runner.busy { ProgressView() } else { Text("Passwort ändern").bold() }
                        Spacer()
                    }
                }
                .disabled(oldPassword.isEmpty || newPassword.count < 6 || runner.busy)
            }
        }
        .settingsPage(regular: sizeClass == .regular)
        .navigationTitle("Passwort ändern")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func changePassword() {
        let old = oldPassword
        let new = newPassword
        runner.run(toasts, success: String(localized: "Passwort geändert – bitte neu anmelden.")) {
            try await store.repository.changePassword(old: old, new: new)
            await store.logout(remote: false)
        }
    }
}

// MARK: - Fees

private struct FeeSettingsPage: View {
    @Environment(AppStore.self) private var store
    @Environment(ToastCenter.self) private var toasts
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var runner = ActionRunner()
    @State private var fees: [String: String] = [:]

    var body: some View {
        List {
            Section {
                ForEach(MemberStatus.paying) { status in
                    LabeledContent(MemberStatus.name(status.rawValue)) {
                        HStack(spacing: 4) {
                            TextField("0,00", text: Binding(get: { fees[status.rawValue] ?? "" }, set: { fees[status.rawValue] = $0 }))
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .frame(maxWidth: 100)
                            Text("€").foregroundStyle(Palette.textSecondary)
                        }
                    }
                }
            } footer: {
                Text("Monatlicher Beitrag je Mitgliedsstatus.")
            }
            Section {
                Button(action: saveFees) {
                    HStack {
                        Spacer()
                        if runner.busy { ProgressView() } else { Text("Beiträge speichern").bold() }
                        Spacer()
                    }
                }
                .disabled(runner.busy)
            }
        }
        .settingsPage(regular: sizeClass == .regular)
        .navigationTitle("Monatliche Beiträge")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            guard fees.isEmpty else { return }
            for status in MemberStatus.paying {
                fees[status.rawValue] = SettingsView.amountText(store.data.fees.rate(for: status.rawValue))
            }
        }
    }

    private func saveFees() {
        var rates: [String: Double] = [:]
        for status in MemberStatus.paying {
            guard let text = fees[status.rawValue], let value = Amount.parse(text), value >= 0 else {
                toasts.show(String(localized: "Ungültiger Betrag."), error: true)
                return
            }
            rates[status.rawValue] = value
        }
        runner.run(toasts, success: String(localized: "Gespeichert")) {
            try await store.repository.saveFeeSettings(rates)
            await store.refreshAll()
        }
    }
}

// MARK: - Calendar

private struct CalendarSettingsPage: View {
    @Environment(AppStore.self) private var store
    @Environment(ToastCenter.self) private var toasts
    @Environment(\.openURL) private var openURL
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var runner = ActionRunner()
    @State private var feed: CalendarFeed?
    @State private var confirmReset = false

    var body: some View {
        List {
            Section {
                if let feed, !feed.feedUrl.isEmpty {
                    Button {
                        UIPasteboard.general.string = feed.feedUrl
                        toasts.show(String(localized: "In die Zwischenablage kopiert"))
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Persönlicher iCal-Link").font(.caption).foregroundStyle(Palette.textSecondary)
                            Text(feed.feedUrl).font(.system(size: 13, design: .monospaced)).foregroundStyle(Palette.text).lineLimit(2)
                        }
                    }
                    if let webcal = URL(string: feed.webcalUrl.isEmpty ? feed.feedUrl.replacingOccurrences(of: "https://", with: "webcal://") : feed.webcalUrl) {
                        Button { openURL(webcal) } label: { Label("Auf diesem Gerät abonnieren", systemImage: "calendar.badge.plus") }
                        if let encoded = webcal.absoluteString.addingPercentEncoding(withAllowedCharacters: .alphanumerics),
                           let google = URL(string: "https://calendar.google.com/calendar/r?cid=\(encoded)") {
                            Button { openURL(google) } label: { Label("In Google Kalender abonnieren", systemImage: "globe") }
                        }
                    }
                    Button("Link erneuern", role: .destructive) { confirmReset = true }
                        .disabled(runner.busy)
                } else {
                    ProgressView().frame(maxWidth: .infinity)
                }
            } footer: {
                Text("Alle Termine und deine Dienste in deiner Kalender-App abonnieren.")
            }
        }
        .settingsPage(regular: sizeClass == .regular)
        .navigationTitle("Kalender-Abonnement")
        .navigationBarTitleDisplayMode(.inline)
        .task { if feed == nil { feed = try? await store.repository.calendarFeed() } }
        .confirmationDialog("Der alte Link funktioniert danach nicht mehr. Bestehende Abos müssen neu eingerichtet werden.",
                            isPresented: $confirmReset, titleVisibility: .visible) {
            Button("Link erneuern", role: .destructive) {
                runner.run(toasts, success: String(localized: "Neuer Link erstellt")) {
                    feed = try await store.repository.resetCalendarFeed()
                }
            }
        }
    }
}

// MARK: - Privacy & account

private struct AccountSettingsPage: View {
    @Environment(AppStore.self) private var store
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var deleting = false

    var body: some View {
        List {
            if let user = store.user {
                Section {
                    if let url = URL(string: store.baseURL + "/privacy") {
                        Link(destination: url) { Label("Datenschutzerklärung", systemImage: "hand.raised") }
                    }
                    if let url = URL(string: store.baseURL) {
                        Link(destination: url) { Label("Im Browser öffnen", systemImage: "safari") }
                    }
                    if user.isAdmin, let url = URL(string: store.baseURL + "/#super-admin-settings") {
                        Link(destination: url) { Label("Systemeinstellungen", systemImage: "shield") }
                    }
                }
                if !user.owner && !user.superAdmin {
                    Section {
                        Button(role: .destructive) { deleting = true } label: { Label("Konto löschen", systemImage: "trash") }
                    } footer: {
                        Text("Löscht deinen Zugang und deine persönlichen Daten. Gebuchte Zahlungen bleiben für die Kassenführung erhalten.")
                    }
                }
            }
        }
        .settingsPage(regular: sizeClass == .regular)
        .navigationTitle("Datenschutz & Konto")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $deleting) { DeleteAccountSheet() }
    }
}

/// Deletes the own account after the password (App Store requirement: deletion inside the app).
struct DeleteAccountSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(ToastCenter.self) private var toasts
    @Environment(\.dismiss) private var dismiss
    @State private var password = ""
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Löscht deinen Zugang und deine persönlichen Daten: Profil, Profilbild, Anmeldungen, Dienste und Mentoring-Gespräche. Gebuchte Zahlungen bleiben für die Kassenführung erhalten. Das kann nicht rückgängig gemacht werden.")
                        .font(.subheadline)
                }
                Section("Passwort zur Bestätigung") {
                    SecureField("Passwort", text: $password).textContentType(.password)
                }
                if let error { Section { Text(error).foregroundStyle(Palette.danger) } }
                Section {
                    Button(role: .destructive, action: delete) {
                        HStack {
                            Spacer()
                            if busy { ProgressView() } else { Text("Konto endgültig löschen").bold() }
                            Spacer()
                        }
                    }
                    .disabled(password.isEmpty || busy)
                }
            }
            .navigationTitle("Konto löschen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } } }
            .interactiveDismissDisabled(busy)
        }
    }

    private func delete() {
        busy = true
        error = nil
        Task {
            defer { busy = false }
            do {
                try await store.repository.deleteAccount(password: password)
                dismiss()
                await store.logout(remote: false)
                toasts.show(String(localized: "Dein Konto wurde gelöscht."))
            } catch {
                self.error = APIError.text(error)
            }
        }
    }
}
