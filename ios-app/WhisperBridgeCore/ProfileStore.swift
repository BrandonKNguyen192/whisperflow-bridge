import Combine
import Foundation
import Security

public struct Profile: Codable, Identifiable, Equatable {
    public var id: UUID
    public var name: String
    public var host: String
    public var port: Int
    public var token: String

    public init(
        id: UUID = UUID(),
        name: String,
        host: String = "",
        port: Int = 9877,
        token: String = ""
    ) {
        self.id = id
        self.name = name
        self.host = host
        self.port = port
        self.token = token
    }
}

/// Profiles with Keychain-backed tokens — non-secret metadata lives in
/// UserDefaults, tokens in the Keychain keyed by profile id.
public final class ProfileStore: ObservableObject {
    @Published public private(set) var profiles: [Profile] = []
    @Published public var activeIndex = 0

    private enum Keys {
        static let profiles = "profiles_json"
        static let active = "active_index"
    }

    private let defaults: UserDefaults
    private let keychainService = "com.whisperbridge.tokens"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        load()
    }

    public var active: Profile? {
        profiles.indices.contains(activeIndex) ? profiles[activeIndex] : nil
    }

    public func setActive(_ index: Int) {
        guard profiles.indices.contains(index) else { return }
        activeIndex = index
        defaults.set(index, forKey: Keys.active)
    }

    public func saveConnection(index: Int, host: String, port: Int, token: String) {
        guard profiles.indices.contains(index) else { return }
        let existing = profiles[index]
        updateKeychainToken(token, for: existing.id)
        profiles[index] = Profile(
            id: existing.id,
            name: existing.name,
            host: host,
            port: port,
            token: token
        )
        persist()
    }

    public func add(name: String, host: String = "", port: Int = 9877, token: String = "") {
        let profile = Profile(name: name, host: host, port: port, token: token)
        updateKeychainToken(token, for: profile.id)
        profiles.append(profile)
        persist()
        setActive(profiles.count - 1)
    }

    public func remove(at index: Int) {
        guard profiles.indices.contains(index), profiles.count > 1 else { return }
        deleteKeychainToken(for: profiles[index].id)
        profiles.remove(at: index)
        persist()
        if activeIndex >= profiles.count {
            activeIndex = max(0, profiles.count - 1)
        } else if activeIndex > index {
            activeIndex -= 1
        }
        defaults.set(activeIndex, forKey: Keys.active)
    }

    // MARK: - Persistence

    private func load() {
        activeIndex = defaults.integer(forKey: Keys.active)
        guard let data = defaults.data(forKey: Keys.profiles),
              let decoded = try? JSONDecoder().decode([Profile].self, from: data) else {
            profiles = []
            return
        }
        profiles = decoded.map { profile in
            var copy = profile
            copy.token = keychainToken(for: profile.id) ?? ""
            return copy
        }
        if activeIndex >= profiles.count {
            activeIndex = max(0, profiles.count - 1)
        }
    }

    private func persist() {
        let sanitized = profiles.map { profile in
            var copy = profile
            copy.token = ""
            return copy
        }
        if let data = try? JSONEncoder().encode(sanitized) {
            defaults.set(data, forKey: Keys.profiles)
        }
    }

    // MARK: - Keychain

    private func account(for id: UUID) -> String {
        "profile.\(id.uuidString)"
    }

    private func updateKeychainToken(_ token: String, for id: UUID) {
        guard let data = token.data(using: .utf8) else { return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: account(for: id)
        ]
        let attributes: [String: Any] = [kSecValueData as String: data]
        var status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var add = query
            add[kSecValueData as String] = data
            status = SecItemAdd(add as CFDictionary, nil)
        }
        _ = status
    }

    private func keychainToken(for id: UUID) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: account(for: id),
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func deleteKeychainToken(for id: UUID) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: account(for: id)
        ]
        SecItemDelete(query as CFDictionary)
    }
}
