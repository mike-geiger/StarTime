import Foundation
import Security

/// Persists Cognito tokens in the Keychain so a session survives app
/// relaunches, mirroring Firebase Auth's automatic session persistence
/// (Cognito itself has no equivalent of `addStateDidChangeListener`).
final class KeychainTokenStore {
    private enum Key: String {
        case idToken = "com.startime.auth.idToken"
        case accessToken = "com.startime.auth.accessToken"
        case refreshToken = "com.startime.auth.refreshToken"
    }

    var idToken: String? { read(.idToken) }
    var accessToken: String? { read(.accessToken) }
    var refreshToken: String? { read(.refreshToken) }

    func save(idToken: String, accessToken: String, refreshToken: String) {
        write(.idToken, idToken)
        write(.accessToken, accessToken)
        write(.refreshToken, refreshToken)
    }

    func clear() {
        for key in [Key.idToken, .accessToken, .refreshToken] {
            SecItemDelete(query(key) as CFDictionary)
        }
    }

    private func query(_ key: Key) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "StarTime",
            kSecAttrAccount as String: key.rawValue,
        ]
    }

    private func read(_ key: Key) -> String? {
        var q = query(key)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func write(_ key: Key, _ value: String) {
        let data = Data(value.utf8)
        if SecItemCopyMatching(query(key) as CFDictionary, nil) == errSecSuccess {
            SecItemUpdate(query(key) as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        } else {
            var newItem = query(key)
            newItem[kSecValueData as String] = data
            SecItemAdd(newItem as CFDictionary, nil)
        }
    }
}
