import SwiftUI
import PhotosUI

/// Settings as a native grouped list.
struct SettingsView: View {
    @Environment(AppStore.self) private var store
    @Environment(ToastCenter.self) private var toasts
    @Environment(\.openURL) private var openURL
    @AppStorage(AppInfo.themeKey) private var theme = ThemeChoice.system.rawValue
    @State private var runner = ActionRunner()
    @State private var photo: PhotosPickerItem?
    @State private var pictureRevision = 0
    @State private var uploading = false
    @State private var inviteCode: String?
    @State private var feed: CalendarFeed?
    @State private var fees: [String: String] = [:]
    @State private var oldPassword = ""
    @State private var newPassword = ""
    @State private var confirmLogout = false
    @State private var confirmResetFeed = false
    @State private var deleting = false

    var body: some View {
        List {
            if let user = store.user {
                profileSection(user)
                if user.managesRegistrationCode { inviteSection }
                notificationSection(user)
                appearanceSection
                if user.isAdmin { feeSection }
                passwordSection
                calendarSection
                accountSection(user)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Palette.background.ignoresSafeArea())
        .navigationTitle("Einstellungen")
        .navigationBarTitleDisplayMode(.large)
        .disabled(runner.busy)
        .task {
            feed = try? await store.repository.calendarFeed()
            if store.user?.managesRegistrationCode == true { inviteCode = await store.repository.inviteCode() }
            for status in MemberStatus.paying {
                fees[status.rawValue] = Self.amountText(store.data.fees.rate(for: status.rawValue))
            }
        }
        .onChange(of: photo) { _, item in upload(item) }
        .confirmationDialog("Abmelden?", isPresented: $confirmLogout, titleVisibility: .visible) {
            Button("Abmelden", role: .destructive) { Task { await store.logout() } }
        }
        .confirmationDialog("Der alte Link funktioniert danach nicht mehr. Bestehende Abos müssen neu eingerichtet werden.",
                            isPresented: $confirmResetFeed, titleVisibility: .visible) {
            Button("Link erneuern", role: .destructive, action: resetFeed)
        }
        .sheet(isPresented: $deleting) { DeleteAccountSheet() }
    }

    // MARK: Sections

    private func profileSection(_ user: User) -> some View {
        Section {
            HStack(spacing: 16) {
                Avatar(userId: user.userId, name: user.fullName, size: 72, ring: user.ring, revision: pictureRevision)
                VStack(alignment: .leading, spacing: 4) {
                    Text(user.fullName).font(.system(size: 18, weight: .bold))
                    Text(user.email).font(.subheadline).foregroundStyle(Palette.textSecondary)
                }
            }
            .padding(.vertical, 6)
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

    private var inviteSection: some View {
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
        } header: {
            Text("Registrierungscode")
        } footer: {
            Text("Mit diesem Code können sich neue Mitglieder registrieren.")
        }
    }

    private func notificationSection(_ user: User) -> some View {
        let settings = user.effectiveNotifications
        return Section {
            toggle("Dienstanfragen", "Anfragen, Bestätigungen & Änderungen deiner Dienste", settings.duties) { $0.duties = $1 }
            toggle("Neue Events & Termine", "Neue Veranstaltungen und Termine der Gemeinde", settings.events) { $0.events = $1 }
            toggle("Nachrichten", "Begleitungsanfragen und Mentoring-Nachrichten", settings.messages) { $0.messages = $1 }
            if user.viewsFinances || user.isAdmin {
                toggle("Finanzielle Anträge", "Neue Kassen- und Erstattungsanträge", settings.finances) { $0.finances = $1 }
            }
        } header: {
            Text("Benachrichtigungen")
        } footer: {
            Text("Benachrichtigungen kommen per E-Mail. Push-Benachrichtigungen für die iOS-App folgen; solange die App geöffnet ist, aktualisiert sie sich live.")
        }
    }

    private func toggle(_ title: LocalizedStringKey, _ subtitle: LocalizedStringKey, _ value: Bool,
                        _ change: @escaping (inout NotificationSettings, Bool) -> Void) -> some View {
        Toggle(isOn: Binding(get: { value }, set: { saveNotifications(change, $0) })) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(subtitle).font(.caption).foregroundStyle(Palette.textSecondary)
            }
        }
        .tint(Palette.secondary)
    }

    private var appearanceSection: some View {
        Section("Darstellung & Sprache") {
            Picker("Farbschema", selection: $theme) {
                ForEach(ThemeChoice.allCases) { Text($0.label).tag($0.rawValue) }
            }
            Button {
                if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
            } label: {
                LabeledContent("Sprache / Language") { Image(systemName: "arrow.up.forward.app").foregroundStyle(Palette.textSecondary) }
            }
            .foregroundStyle(Palette.text)
        }
    }

    private var feeSection: some View {
        Section {
            ForEach(MemberStatus.paying) { status in
                LabeledContent(status.label) {
                    HStack(spacing: 4) {
                        TextField("0,00", text: Binding(get: { fees[status.rawValue] ?? "" }, set: { fees[status.rawValue] = $0 }))
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 100)
                        Text("€").foregroundStyle(Palette.textSecondary)
                    }
                }
            }
            Button("Beiträge speichern", action: saveFees)
        } header: {
            Text("Monatliche Beiträge")
        }
    }

    private var passwordSection: some View {
        Section("Passwort ändern") {
            SecureField("Altes Passwort", text: $oldPassword).textContentType(.password)
            SecureField("Neues Passwort (min. 6)", text: $newPassword).textContentType(.newPassword)
            Button("Passwort ändern", action: changePassword)
                .disabled(oldPassword.isEmpty || newPassword.count < 6)
        }
    }

    private var calendarSection: some View {
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
                Button("Link erneuern", role: .destructive) { confirmResetFeed = true }
            } else {
                ProgressView()
            }
        } header: {
            Text("Kalender-Abonnement")
        } footer: {
            Text("Alle Termine und deine Dienste in deiner Kalender-App abonnieren.")
        }
    }

    private func accountSection(_ user: User) -> some View {
        Section {
            if let url = URL(string: store.baseURL) {
                Link(destination: url) { Label("Im Browser öffnen", systemImage: "safari") }
            }
            if user.isAdmin, let url = URL(string: store.baseURL + "/#super-admin-settings") {
                Link(destination: url) { Label("Systemeinstellungen", systemImage: "shield") }
            }
            if let url = URL(string: store.baseURL + "/privacy") {
                Link(destination: url) { Label("Datenschutzerklärung", systemImage: "hand.raised") }
            }
            Button(role: .destructive) { confirmLogout = true } label: {
                Label("Abmelden", systemImage: "rectangle.portrait.and.arrow.right")
            }
            if !user.owner && !user.superAdmin {
                Button(role: .destructive) { deleting = true } label: { Label("Konto löschen", systemImage: "trash") }
            }
        } header: {
            Text("Konto")
        } footer: {
            Text("Agora iOS \(AppInfo.version)").frame(maxWidth: .infinity).padding(.top, 12)
        }
    }

    // MARK: Actions

    private static func amountText(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(2)).locale(Locale(identifier: "de_DE")))
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

    private func newInviteCode() {
        let code = String(Int.random(in: 100_000...999_999))
        runner.run(toasts, success: String(localized: "Gespeichert")) {
            try await store.repository.setInviteCode(code)
            inviteCode = code
        }
    }

    private func saveNotifications(_ change: @escaping (inout NotificationSettings, Bool) -> Void, _ value: Bool) {
        guard let user = store.user else { return }
        var settings = user.effectiveNotifications
        change(&settings, value)
        let updated = settings
        runner.run(toasts) {
            try await store.repository.saveNotificationSettings(uid: user.userId, updated)
            try await store.reloadUser()
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

    private func changePassword() {
        let old = oldPassword
        let new = newPassword
        runner.run(toasts, success: String(localized: "Passwort geändert – bitte neu anmelden.")) {
            try await store.repository.changePassword(old: old, new: new)
            await store.logout(remote: false)
        }
    }

    private func resetFeed() {
        runner.run(toasts, success: String(localized: "Neuer Link erstellt")) {
            feed = try await store.repository.resetCalendarFeed()
        }
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
