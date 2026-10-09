import Foundation
import Security

/// Holds the session token. Survives app deletion only as long as the Keychain does; signing
/// in again with the passkey always replaces it.
protocol SessionStore: Sendable {
    func loadToken() -> String?
    func saveToken(_ token: String)
    func clearToken()
}

struct KeychainSessionStore: SessionStore {
    let service: String

    init(service: String = "com.bhuvanrj.midas.session") {
        self.service = service
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: "session-token",
        ]
    }

    func loadToken() -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    func saveToken(_ token: String) {
        clearToken()
        var query = baseQuery
        query[kSecValueData as String] = Data(token.utf8)
        // Not synced to other devices: each phone signs in with the passkey and gets its own session.
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(query as CFDictionary, nil)
    }

    func clearToken() {
        SecItemDelete(baseQuery as CFDictionary)
    }
}
