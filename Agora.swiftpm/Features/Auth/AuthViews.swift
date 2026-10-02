import SwiftUI

/// Login background of the web app: light page with a cyan and an emerald glow.
struct AuthBackground: View {
    var body: some View {
        ZStack {
            Palette.background
            RadialGradient(colors: [Color(hex: 0x06B6D4, opacity: 0.15), .clear], center: .topLeading, startRadius: 0, endRadius: 420)
            RadialGradient(colors: [Color(hex: 0x10B981, opacity: 0.15), .clear], center: .bottomTrailing, startRadius: 0, endRadius: 420)
        }
        .ignoresSafeArea()
    }
}

/// Text field with a leading icon in the web app's input style (2 px border, cyan on focus).
struct IconField: View {
    let title: LocalizedStringKey
    let systemImage: String
    @Binding var text: String
    var secure = false
    var content: UITextContentType?
    var keyboard: UIKeyboardType = .default
    var capitalization: TextInputAutocapitalization = .sentences
    var submitLabel: SubmitLabel = .next
    var onSubmit: () -> Void = {}
    @FocusState private var focused: Bool
    @State private var revealed = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(focused ? Palette.primary : Palette.textSecondary)
                .frame(width: 22)
            Group {
                if secure && !revealed {
                    SecureField(title, text: $text)
                } else {
                    TextField(title, text: $text)
                        .keyboardType(keyboard)
                        .textInputAutocapitalization(capitalization)
                }
            }
            .textContentType(content)
            .autocorrectionDisabled()
            .focused($focused)
            .submitLabel(submitLabel)
            .onSubmit(onSubmit)
            if secure {
                Button { revealed.toggle() } label: {
                    Image(systemName: revealed ? "eye.slash" : "eye").foregroundStyle(Palette.textSecondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(revealed ? "Passwort verbergen" : "Passwort anzeigen")
            }
        }
        .font(.system(size: 16))
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
        .background(focused ? Palette.surface : Palette.surfaceAlt, in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.control, style: .continuous).strokeBorder(focused ? Palette.primary : Palette.border, lineWidth: 2))
        .animation(.easeOut(duration: 0.15), value: focused)
    }
}

/// First start: which Agora server (the address the community opens in the browser).
struct ServerView: View {
    @Environment(AppStore.self) private var store
    @State private var address = ""
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        ZStack {
            AuthBackground()
            ScrollView {
                VStack(spacing: 20) {
                    VStack(spacing: 12) {
                        AppMark(size: 56)
                        GradientText(text: "Agora", size: 34)
                    }
                    .padding(.top, 40)
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Mit deiner Gemeinde verbinden").font(.system(size: 22, weight: .heavy)).foregroundStyle(Palette.text)
                        Text("Gib die Adresse deines Agora-Servers ein – dieselbe, die du im Browser öffnest.")
                            .font(.system(size: 15)).foregroundStyle(Palette.textSecondary)
                        IconField(title: "agora.gemeinde.de", systemImage: "globe", text: $address, content: .URL, keyboard: .URL,
                                  capitalization: .never, submitLabel: .go, onSubmit: connect)
                        if let error {
                            Text(error).font(.system(size: 14, weight: .semibold)).foregroundStyle(Palette.danger)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Button(action: connect) { BusyLabel(title: "Verbinden", busy: busy) }
                            .buttonStyle(.agoraPrimary)
                            .disabled(busy || address.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    .card(padding: 24)
                }
                .padding(20)
                .frame(maxWidth: 440)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .onAppear {
            if address.isEmpty { address = store.baseURL.replacingOccurrences(of: "https://", with: "") }
        }
    }

    private func connect() {
        guard !busy else { return }
        busy = true
        error = nil
        Task {
            defer { busy = false }
            do {
                try await store.connect(address)
            } catch let api as APIError where api.status == 503 || api.status == 426 {
                error = api.message
            } catch let api as APIError {
                error = api.message.isEmpty ? "Agora-Server nicht erreichbar" : "Agora-Server nicht erreichbar (\(api.message))"
            } catch {
                self.error = "Agora-Server nicht erreichbar"
            }
        }
    }
}

/// Login and registration (invite code), like the web app's login modal.
struct LoginView: View {
    let baseURL: String
    @Environment(AppStore.self) private var store

    enum Mode: Hashable { case login, register }
    private enum Field: Hashable { case email, password, code, first, last, repeatPassword }

    @State private var mode: Mode = .login
    @State private var email = ""
    @State private var password = ""
    @State private var code = ""
    @State private var firstName = ""
    @State private var lastName = ""
    @State private var repeatPassword = ""
    @State private var busy = false
    @State private var error: String?

    private var host: String { URL(string: baseURL)?.host ?? baseURL }

    var body: some View {
        ZStack {
            AuthBackground()
            ScrollView {
                VStack(spacing: 0) {
                    VStack(spacing: 22) {
                        VStack(spacing: 8) {
                            HStack(spacing: 12) {
                                ServerLogo(size: 40)
                                GradientText(text: store.appName, size: 32)
                            }
                            Text(mode == .login ? "Melden Sie sich an, um fortzufahren" : "Erstellen Sie ein neues Konto")
                                .font(.system(size: 15, weight: .medium)).foregroundStyle(Palette.textSecondary)
                        }
                        PillTabs(items: [.init(value: Mode.login, title: "Login"), .init(value: Mode.register, title: "Registrieren")], selection: $mode)
                        VStack(spacing: 12) {
                            if mode == .register { registerFields } else { loginFields }
                        }
                        if let error {
                            Text(error).font(.system(size: 14, weight: .bold)).foregroundStyle(Palette.danger)
                                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                        }
                        Button(action: submit) { BusyLabel(title: mode == .login ? "Anmelden" : "Registrieren", busy: busy) }
                            .buttonStyle(.agoraPrimary)
                            .disabled(busy)
                    }
                    .card(padding: 24)
                    Button { store.changeServer() } label: {
                        Text("\(host) · Server wechseln").font(.system(size: 14, weight: .semibold)).foregroundStyle(Palette.textSecondary)
                    }
                    .padding(.top, 18)
                }
                .padding(20)
                .padding(.top, 30)
                .frame(maxWidth: 440)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .onChange(of: mode) { _, _ in error = nil }
    }

    private var loginFields: some View {
        Group {
            IconField(title: "E-Mail", systemImage: "envelope", text: $email, content: .username, keyboard: .emailAddress, capitalization: .never)
            IconField(title: "Passwort", systemImage: "lock", text: $password, secure: true, content: .password, submitLabel: .go, onSubmit: submit)
        }
    }

    private var registerFields: some View {
        Group {
            Text("Den 6-stelligen Registrierungscode erhältst du von deiner Gemeinde.")
                .font(.system(size: 14)).foregroundStyle(Palette.textSecondary).multilineTextAlignment(.center)
                .padding(12)
                .frame(maxWidth: .infinity)
                .background(Palette.surfaceAlt, in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Radius.control, style: .continuous).strokeBorder(Palette.border, style: StrokeStyle(lineWidth: 1, dash: [5, 4])))
            IconField(title: "6-stelliger Code", systemImage: "shippingbox", text: $code, content: .oneTimeCode, keyboard: .numberPad)
                .onChange(of: code) { _, value in
                    let digits = String(value.filter(\.isNumber).prefix(6))
                    if digits != value { code = digits }
                }
            IconField(title: "E-Mail", systemImage: "envelope", text: $email, content: .username, keyboard: .emailAddress, capitalization: .never)
            HStack(spacing: 12) {
                IconField(title: "Vorname", systemImage: "person", text: $firstName, content: .givenName, capitalization: .words)
                IconField(title: "Nachname", systemImage: "person", text: $lastName, content: .familyName, capitalization: .words)
            }
            IconField(title: "Passwort (min. 6)", systemImage: "lock", text: $password, secure: true, content: .newPassword)
            IconField(title: "Passwort wiederholen", systemImage: "lock", text: $repeatPassword, secure: true, content: .newPassword, submitLabel: .go, onSubmit: submit)
        }
    }

    private func submit() {
        guard !busy else { return }
        error = nil
        let mail = email.trimmingCharacters(in: .whitespaces)
        if mode == .register {
            if [code, mail, firstName, lastName, password, repeatPassword].contains(where: { $0.trimmingCharacters(in: .whitespaces).isEmpty }) {
                error = "Bitte alle Felder ausfüllen."
                return
            }
            if password.count < 6 { error = "Das Passwort muss mindestens 6 Zeichen lang sein."; return }
            if password != repeatPassword { error = "Die Passwörter stimmen nicht überein."; return }
        } else if mail.isEmpty || password.isEmpty {
            error = "Bitte alle Felder ausfüllen."
            return
        }
        busy = true
        Task {
            defer { busy = false }
            do {
                if mode == .login {
                    try await store.login(email: mail, password: password)
                } else {
                    try await store.register(code: code, email: mail, firstName: firstName, lastName: lastName, password: password)
                }
            } catch {
                self.error = APIError.text(error)
            }
        }
    }
}
