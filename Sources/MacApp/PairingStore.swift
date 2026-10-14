import Foundation
import Security
import ControlCore

/// Only the most recently authenticated companion is cached. A connection always
/// asks the selected, authorized device for its current credentials first.
enum PairingStore {
    private static let lock = NSLock()

    // Existing entries use the macOS file-based keychain. LAContext alone does
    // not suppress its ACL prompts. Serialize our operations while disabling
    // optional UI for this process, then restore the previous setting.
    private static func withoutInteraction<T>(fallback: T, _ operation: () -> T) -> T {
        lock.lock(); defer { lock.unlock() }
        var previous: DarwinBoolean = true
        guard SecKeychainGetUserInteractionAllowed(&previous) == errSecSuccess,
              SecKeychainSetUserInteractionAllowed(false) == errSecSuccess else { return fallback }
        defer { _ = SecKeychainSetUserInteractionAllowed(previous.boolValue) }
        return operation()
    }

    private static func query(_ account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "org.openinput.UniversalControlAndroid.companion",
         kSecAttrAccount as String: account]
    }
    static func load(account: String = "last-companion") -> CompanionCredentials? {
        return withoutInteraction(fallback: nil) {
            var q = query(account)
            q[kSecReturnData as String] = true
            q[kSecMatchLimit as String] = kSecMatchLimitOne
            var result: CFTypeRef?
            guard SecItemCopyMatching(q as CFDictionary, &result) == errSecSuccess,
                  let data = result as? Data else { return nil }
            return try? JSONDecoder().decode(CompanionCredentials.self, from: data)
        }
    }
    static func save(_ credentials: CompanionCredentials, account: String = "last-companion") -> Bool {
        return withoutInteraction(fallback: false) {
            guard let data = try? JSONEncoder().encode(credentials) else { return false }
            let attributes = [kSecValueData as String: data]
            let status = SecItemUpdate(query(account) as CFDictionary, attributes as CFDictionary)
            if status == errSecSuccess { return true }
            guard status == errSecItemNotFound else { return false }
            var q = query(account); q[kSecValueData as String] = data
            q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            return SecItemAdd(q as CFDictionary, nil) == errSecSuccess
        }
    }
    @discardableResult
    static func forget(account: String = "last-companion") -> Bool {
        withoutInteraction(fallback: false) {
            let status = SecItemDelete(query(account) as CFDictionary)
            return status == errSecSuccess || status == errSecItemNotFound
        }
    }
}
