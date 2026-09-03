import Foundation
import CryptoKit

/// The cryptography behind end-to-end encrypted backup.
///
/// The scheme, in one paragraph: a random 256-bit **data encryption key (DEK)**
/// is generated on-device and encrypts every journal entry with AES-GCM. The
/// DEK itself is never uploaded in the clear — it is sealed under a **key
/// encryption key (KEK)** derived from the user's recovery phrase, and only that
/// sealed blob reaches Supabase. The server therefore holds ciphertext and a
/// wrapped key whose unwrapping material it has never seen.
///
/// Two keys rather than one because it lets the user change their recovery phrase
/// without re-encrypting years of entries: rewrap the DEK, leave the rest.
enum JournalCrypto {
    /// Bumped if the scheme ever changes, so an old client meeting new
    /// ciphertext fails loudly instead of decrypting garbage.
    static let version = 1

    // MARK: - Keys

    static func newDataKey() -> SymmetricKey {
        SymmetricKey(size: .bits256)
    }

    static func newSalt(byteCount: Int = 16) -> Data {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        // A salt that silently came back all-zeroes would weaken every derived
        // key, so a failure here has to be fatal rather than shrugged off.
        guard SecRandomCopyBytes(kSecRandomDefault, byteCount, &bytes) == errSecSuccess else {
            fatalError("The system random number generator is unavailable.")
        }
        return Data(bytes)
    }

    /// Derives the key-encryption key from a recovery phrase.
    ///
    /// HKDF is enough here — and PBKDF2/Argon2 would be theatre — because the
    /// input is 128 bits of machine-generated randomness, not a human-chosen
    /// password. There is nothing to brute-force faster than the keyspace. If
    /// this ever accepts a user-chosen passphrase, it must move to Argon2id.
    static func keyEncryptionKey(recovery: Data, salt: Data) -> SymmetricKey {
        HKDF<SHA256>.deriveKey(
            inputKeyMaterial: SymmetricKey(data: recovery),
            salt: salt,
            info: Data("dawn.backup.kek.v\(version)".utf8),
            outputByteCount: 32
        )
    }

    // MARK: - Sealing

    /// Encrypts with AES-GCM and returns nonce + ciphertext + tag in one blob.
    ///
    /// A fresh random nonce per call is what keeps GCM safe; never make this
    /// take a caller-supplied nonce.
    static func seal(_ plaintext: Data, using key: SymmetricKey) throws -> Data {
        let box = try AES.GCM.seal(plaintext, using: key)
        guard let combined = box.combined else {
            throw BackupFailure.corruptData
        }
        return combined
    }

    /// Decrypts a blob produced by `seal`. GCM authenticates as it decrypts, so
    /// tampered or truncated ciphertext throws rather than returning junk.
    static func open(_ combined: Data, using key: SymmetricKey) throws -> Data {
        do {
            let box = try AES.GCM.SealedBox(combined: combined)
            return try AES.GCM.open(box, using: key)
        } catch {
            // Wrong key and mangled bytes are indistinguishable at this layer,
            // and the caller only ever has one useful response to either.
            throw BackupFailure.corruptData
        }
    }

    // MARK: - Wrapping the data key

    static func wrap(dataKey: SymmetricKey, recovery: Data, salt: Data) throws -> Data {
        let kek = keyEncryptionKey(recovery: recovery, salt: salt)
        let raw = dataKey.withUnsafeBytes { Data($0) }
        return try seal(raw, using: kek)
    }

    static func unwrap(wrapped: Data, recovery: Data, salt: Data) throws -> SymmetricKey {
        let kek = keyEncryptionKey(recovery: recovery, salt: salt)
        do {
            let raw = try open(wrapped, using: kek)
            guard raw.count == 32 else { throw BackupFailure.corruptData }
            return SymmetricKey(data: raw)
        } catch {
            // The phrase's own checksum has already caught typos by the time
            // we get here, so the likely cause is a phrase from another
            // account rather than a mistake — say that, not "corrupt".
            throw BackupFailure.wrongRecoveryPhrase
        }
    }
}
