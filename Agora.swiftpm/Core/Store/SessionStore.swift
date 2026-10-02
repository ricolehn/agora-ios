import Foundation
import Security

/// Saved session: server address, account and app name in UserDefaults, the token in the Keychain.
final class SessionStore: @unchecked Sendable {
    private let defaults: UserDefaults
    private let keychain: TokenStore

    private enum Keys {
        static let baseURL = "agora.baseURL"
        static let user = "agora.user"
        static let appName = "agora.appName"
    }

    init(defaults: UserDefaults = .standard, keychain: TokenStore = TokenStore()) {
        self.defaults = defaults
        self.keychain = keychain
    }

    struct Saved {
        var baseURL: String
        var token: String?
        var user: User?
    }

    func current() -> Saved {
        let user = defaults.data(forKey: Keys.user).flatMap { try? JSONDecoder().decode(User.self, from: $0) }
        return Saved(baseURL: defaults.string(forKey: Keys.baseURL) ?? "", token: keychain.read(), user: user)
    }

    var appName: String? { defaults.string(forKey: Keys.appName) }

    func setAppName(_ name: String) { defaults.set(name, forKey: Keys.appName) }

    func setBaseURL(_ url: String) { defaults.set(url, forKey: Keys.baseURL) }

    func setSession(token: String, user: User) {
        keychain.write(token)
        updateUser(user)
    }

    func updateUser(_ user: User) {
        if let data = try? JSONEncoder().encode(user) { defaults.set(data, forKey: Keys.user) }
    }

    func clearSession() {
        keychain.delete()
        defaults.removeObject(forKey: Keys.user)
    }
}

/// The token in the Keychain (only this device, available after the first unlock so background refreshes work).
struct TokenStore: Sendable {
    var service = "org.agora.app.session"

    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: "token"]
    }

    func read() -> String? {
        var item: CFTypeRef?
        var search = query
        search[kSecReturnData as String] = true
        search[kSecMatchLimit as String] = kSecMatchLimitOne
        guard SecItemCopyMatching(search as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func write(_ token: String) {
        let data = Data(token.utf8)
        let update: [String: Any] = [kSecValueData as String: data]
        if SecItemUpdate(query as CFDictionary, update as CFDictionary) == errSecItemNotFound {
            var add = query
            add[kSecValueData as String] = data
            add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            SecItemAdd(add as CFDictionary, nil)
        }
    }

    func delete() {
        SecItemDelete(query as CFDictionary)
    }
}

/// Last loaded member data on the device, so the app opens with it at once and refreshes in the background.
/// Bound to server and account; excluded from backups (it holds finance data) and cleared on logout.
final class DataCache: @unchecked Sendable {
    private struct Snapshot: Codable {
        var baseURL: String
        var userId: String
        var data: AppData
    }

    private let file: URL

    init(directory: URL? = nil) {
        let base = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        file = base.appendingPathComponent("app-data.json")
    }

    func load(baseURL: String, userId: String) -> AppData? {
        guard let data = try? Data(contentsOf: file),
              let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data),
              snapshot.baseURL == baseURL, snapshot.userId == userId else { return nil }
        return snapshot.data
    }

    func save(baseURL: String, userId: String, data: AppData) {
        guard let encoded = try? JSONEncoder().encode(Snapshot(baseURL: baseURL, userId: userId, data: data)) else { return }
        try? encoded.write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        var url = file
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? url.setResourceValues(values)
    }

    func clear() {
        try? FileManager.default.removeItem(at: file)
    }
}
