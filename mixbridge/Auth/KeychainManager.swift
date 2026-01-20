import Foundation
import Security

/// Manages secure storage of OAuth tokens in iOS Keychain
final class KeychainManager {
    nonisolated static let shared = KeychainManager()

    private init() {}

    private enum Keys {
        static let accessToken = "com.mixbridge.soundcloud.accessToken"
        static let refreshToken = "com.mixbridge.soundcloud.refreshToken"
        static let tokenExpiry = "com.mixbridge.soundcloud.tokenExpiry"
        static let userId = "com.mixbridge.soundcloud.userId"
        static let username = "com.mixbridge.soundcloud.username"
        static let provider = "com.mixbridge.auth.provider"
    }

    // MARK: - Save

    func saveAccessToken(_ token: String) throws {
        try saveString(token, forKey: Keys.accessToken)
    }

    func saveRefreshToken(_ token: String) throws {
        try saveString(token, forKey: Keys.refreshToken)
    }

    func saveTokenExpiry(_ date: Date) throws {
        let timestamp = date.timeIntervalSince1970
        try saveString(String(timestamp), forKey: Keys.tokenExpiry)
    }

    func saveUserId(_ userId: String) throws {
        try saveString(userId, forKey: Keys.userId)
    }

    func saveUsername(_ username: String) throws {
        try saveString(username, forKey: Keys.username)
    }

    func saveProvider(_ provider: String) throws {
        try saveString(provider, forKey: Keys.provider)
    }

    // MARK: - Retrieve

    func getAccessToken() -> String? {
        return getString(forKey: Keys.accessToken)
    }

    func getRefreshToken() -> String? {
        return getString(forKey: Keys.refreshToken)
    }

    func getTokenExpiry() -> Date? {
        guard let timestampString = getString(forKey: Keys.tokenExpiry),
              let timestamp = Double(timestampString) else {
            return nil
        }
        return Date(timeIntervalSince1970: timestamp)
    }

    func getUserId() -> String? {
        return getString(forKey: Keys.userId)
    }

    func getUsername() -> String? {
        return getString(forKey: Keys.username)
    }

    func getProvider() -> String? {
        return getString(forKey: Keys.provider)
    }

    // MARK: - Delete

    func clearAllTokens() {
        deleteItem(forKey: Keys.accessToken)
        deleteItem(forKey: Keys.refreshToken)
        deleteItem(forKey: Keys.tokenExpiry)
        deleteItem(forKey: Keys.userId)
        deleteItem(forKey: Keys.username)
        deleteItem(forKey: Keys.provider)
    }

    // MARK: - Private Helpers

    private func saveString(_ value: String, forKey key: String) throws {
        guard let data = value.data(using: .utf8) else {
            throw KeychainError.encodingFailed
        }

        // Delete existing item first
        deleteItem(forKey: key)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]

        let status = SecItemAdd(query as CFDictionary, nil)

        guard status == errSecSuccess else {
            throw KeychainError.saveFailed(status)
        }
    }

    private func getString(forKey key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let string = String(data: data, encoding: .utf8) else {
            return nil
        }

        return string
    }

    private func deleteItem(forKey key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key
        ]

        SecItemDelete(query as CFDictionary)
    }
}

// MARK: - Errors

enum KeychainError: LocalizedError {
    case encodingFailed
    case saveFailed(OSStatus)
    case deleteFailed(OSStatus)

    var errorDescription: String? {
        switch self {
        case .encodingFailed:
            return "Failed to encode data"
        case .saveFailed(let status):
            return "Failed to save to keychain: \(status)"
        case .deleteFailed(let status):
            return "Failed to delete from keychain: \(status)"
        }
    }
}
