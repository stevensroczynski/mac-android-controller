import Foundation
import Security
import LocalAuthentication
import ControlCore

/// Only the most recently authenticated companion is cached. A connection always
/// asks the selected, authorized device for its current credentials first.
enum PairingStore {
    private static func query(_ account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "org.openinput.UniversalControlAndroid.companion",
         kSecAttrAccount as String: account]
    }
    static func load(account: String = "last-companion") -> CompanionCredentials? {
        var q = query(account)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        let context = LAContext(); context.interactionNotAllowed = true
        q[kSecUseAuthenticationContext as String] = context
        var result: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return try? JSONDecoder().decode(CompanionCredentials.self, from: data)
    }
    static func save(_ credentials: CompanionCredentials, account: String = "last-companion") -> Bool {
        guard let data = try? JSONEncoder().encode(credentials) else { return false }
        let attributes = [kSecValueData as String: data]
        let status = SecItemUpdate(query(account) as CFDictionary, attributes as CFDictionary)
        if status == errSecSuccess { return true }
        guard status == errSecItemNotFound else { return false }
        var q = query(account); q[kSecValueData as String] = data
        q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return SecItemAdd(q as CFDictionary, nil) == errSecSuccess
    }
    static func forget(account: String = "last-companion") { SecItemDelete(query(account) as CFDictionary) }
}
