import Foundation
import Supabase

/// The only type that talks to the backup tables.
///
/// Note what crosses this boundary: base64 blobs and dates. If a future change
/// ever puts a readable field in one of these structs, the end-to-end promise
/// is broken at that moment — so keep them boring.
struct BackupClient {
    private let client: SupabaseClient

    init?(client: SupabaseClient? = SupabaseStack.shared) {
        guard let client else { return nil }
        self.client = client
    }

    // MARK: - Wire types

    struct KeyRow: Codable {
        var userID: String
        var wrappedDEK: String
        var kdfSalt: String

        enum CodingKeys: String, CodingKey {
            case userID = "user_id"
            case wrappedDEK = "wrapped_dek"
            case kdfSalt = "kdf_salt"
        }
    }

    struct EntryRow: Codable {
        var userID: String
        var day: String
        var ciphertext: String
        /// Sent and received as a string so this never depends on how the SDK
        /// happens to configure date decoding today.
        var updatedAt: String

        enum CodingKeys: String, CodingKey {
            case userID = "user_id"
            case day
            case ciphertext
            case updatedAt = "updated_at"
        }
    }

    // MARK: - Keys

    func fetchKey(for userID: String) async throws -> KeyRow? {
        do {
            let rows: [KeyRow] = try await client
                .from("encryption_keys")
                .select("user_id,wrapped_dek,kdf_salt")
                .eq("user_id", value: userID)
                .limit(1)
                .execute()
                .value
            return rows.first
        } catch {
            throw Self.mapped(error)
        }
    }

    /// First-time upload only. `insert` rather than `upsert` on purpose: if a
    /// key already exists, this must fail loudly rather than overwrite it, or a
    /// second device racing setup would strand every entry written under the
    /// first device's data key.
    func storeKey(_ row: KeyRow) async throws {
        do {
            try await client.from("encryption_keys").insert(row).execute()
        } catch {
            throw Self.mapped(error)
        }
    }

    /// Replaces the wrapping only. Safe because the caller re-wraps the *same*
    /// data key under a new recovery phrase — the entries are untouched, so this
    /// cannot strand them the way overwriting in `storeKey` would.
    func replaceKeyWrapping(_ row: KeyRow) async throws {
        do {
            try await client
                .from("encryption_keys")
                .upsert(row, onConflict: "user_id")
                .execute()
        } catch {
            throw Self.mapped(error)
        }
    }

    // MARK: - Settings

    struct SettingsRow: Codable {
        var userID: String
        var ciphertext: String
        var updatedAt: String

        enum CodingKeys: String, CodingKey {
            case userID = "user_id"
            case ciphertext
            case updatedAt = "updated_at"
        }
    }

    func fetchSettings(for userID: String) async throws -> SettingsRow? {
        do {
            let rows: [SettingsRow] = try await client
                .from("user_settings")
                .select("user_id,ciphertext,updated_at")
                .eq("user_id", value: userID)
                .limit(1)
                .execute()
                .value
            return rows.first
        } catch {
            throw Self.mapped(error)
        }
    }

    func uploadSettings(_ row: SettingsRow) async throws {
        do {
            try await client
                .from("user_settings")
                .upsert(row, onConflict: "user_id")
                .execute()
        } catch {
            throw Self.mapped(error)
        }
    }

    func deleteSettings(for userID: String) async throws {
        do {
            try await client
                .from("user_settings")
                .delete()
                .eq("user_id", value: userID)
                .execute()
        } catch {
            throw Self.mapped(error)
        }
    }

    // MARK: - Entries

    func fetchEntries(for userID: String) async throws -> [EntryRow] {
        do {
            return try await client
                .from("journal_entries")
                .select("user_id,day,ciphertext,updated_at")
                .eq("user_id", value: userID)
                .execute()
                .value
        } catch {
            throw Self.mapped(error)
        }
    }

    /// Removes every backed-up entry for this user.
    ///
    /// Only used by "start over", where the data key is gone for good and the
    /// rows are permanently unreadable. They can't be left behind: `sync`
    /// treats an undecryptable row as a hard error, so orphaned ciphertext
    /// would break syncing for the account forever.
    func deleteAllEntries(for userID: String) async throws {
        do {
            try await client
                .from("journal_entries")
                .delete()
                .eq("user_id", value: userID)
                .execute()
        } catch {
            throw Self.mapped(error)
        }
    }

    /// Removes one day's row, after the user deleted that entry on a device.
    ///
    /// Nothing here is a tombstone: the row simply stops existing, so any other
    /// device that still holds the day will push it back on its next sync. That
    /// is the accepted limit of a scheme with no server-side history, and the
    /// window is the time between the two devices syncing.
    func deleteEntry(for userID: String, day: String) async throws {
        do {
            try await client
                .from("journal_entries")
                .delete()
                .eq("user_id", value: userID)
                .eq("day", value: day)
                .execute()
        } catch {
            throw Self.mapped(error)
        }
    }

    func upload(_ rows: [EntryRow]) async throws {
        guard !rows.isEmpty else { return }
        do {
            try await client
                .from("journal_entries")
                .upsert(rows, onConflict: "user_id,day")
                .execute()
        } catch {
            throw Self.mapped(error)
        }
    }

    // MARK: - Mapping

    private static func mapped(_ error: Error) -> BackupFailure {
        if let failure = error as? BackupFailure { return failure }
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain { return .network }
        let text = error.localizedDescription.lowercased()
        if text.contains("network") || text.contains("offline") || text.contains("connection") {
            return .network
        }
        return .server(error.localizedDescription)
    }
}
