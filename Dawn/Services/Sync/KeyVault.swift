import Foundation
import Security
import CryptoKit

/// Stores the data encryption key in the keychain, so the recovery phrase is
/// needed once and then effectively never again.
///
/// The item is marked synchronizable, which puts it in iCloud Keychain — itself
/// end-to-end encrypted by Apple, with keys we never hold. That is what makes a
/// second device Just Work while keeping the promise intact: at no point does a
/// readable key pass through our servers.
///
/// Synchronizable items cannot use a `ThisDeviceOnly` protection class, so this
/// is `AfterFirstUnlock`: readable in the background after one unlock following
/// a reboot, which the morning alarm path needs.
enum KeyVault {
    private static let service = "com.sulav.journalblock.backup-key"

    // MARK: - Reading

    static func dataKey(for userID: String) -> SymmetricKey? {
        var query = baseQuery(for: userID)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data,
              data.count == 32
        else { return nil }
        return SymmetricKey(data: data)
    }

    // MARK: - Writing

    static func store(_ key: SymmetricKey, for userID: String) throws {
        let raw = key.withUnsafeBytes { Data($0) }

        // Delete-then-add rather than SecItemUpdate: an update can't change the
        // accessibility attributes of an item written by an older build, and a
        // stale one would lock us out of our own key after a reboot.
        SecItemDelete(baseQuery(for: userID) as CFDictionary)

        var query = baseQuery(for: userID)
        query[kSecValueData as String] = raw
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw BackupFailure.keychain(status) }
    }

    /// Called on sign-out. The key stays recoverable from the recovery phrase, so
    /// removing it here loses nothing but does stop the next person to hold the
    /// phone from reading the last user's journal.
    static func remove(for userID: String) {
        SecItemDelete(baseQuery(for: userID) as CFDictionary)
    }

    // MARK: - Plumbing

    private static func baseQuery(for userID: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: userID,
            kSecAttrSynchronizable as String: true
        ]
    }
}
