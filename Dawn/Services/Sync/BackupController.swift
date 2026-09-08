import Foundation
import Observation
import CryptoKit

/// Owns the encrypted backup: whether it's set up, whether this device can
/// read it, and moving days between here and Supabase.
///
/// The design constraint that shapes everything below: we cannot help a user
/// who has lost both their keychain and their recovery phrase. No support path,
/// no reset, no "verify your email and we'll restore it". That is what makes
/// the privacy claim true, and every screen that touches this has to be honest
/// about it rather than burying it.
@Observable
@MainActor
final class BackupController {
    enum Status: Equatable {
        /// No Supabase keys in the build, or nobody signed in.
        case unavailable
        /// Signed in, but this account has never set up a backup.
        case needsSetup
        /// A backup exists and this device can't read it without the code.
        case locked
        case ready
    }

    private(set) var status: Status = .unavailable
    private(set) var isWorking = false
    private(set) var lastSyncedAt: Date?
    /// Surfaced to the UI after a failed sync. Cleared on the next success.
    private(set) var lastError: BackupFailure?
    /// Set when the user dropped the key themselves, so the launch prompt
    /// doesn't immediately ask them to put back what they just chose to remove.
    private(set) var didDeliberatelyForget = false

    /// Whether this account has ever been handed a phrase it could write down.
    /// False after a plain `enable`, which issues none — so the UI can offer to
    /// mint one rather than talking about replacing a phrase that never existed.
    var hasIssuedPhrase: Bool {
        get {
            guard let userID else { return false }
            return UserDefaults.standard.bool(forKey: "backup.phrase.issued.\(userID)")
        }
        set {
            guard let userID else { return }
            UserDefaults.standard.set(newValue, forKey: "backup.phrase.issued.\(userID)")
        }
    }

    @ObservationIgnored private let client: BackupClient?
    @ObservationIgnored private var dataKey: SymmetricKey?
    @ObservationIgnored private var userID: String?

    init(client: BackupClient? = BackupClient()) {
        self.client = client
    }

    var isConfigured: Bool { client != nil }

    /// Something is wrong that the user can act on. Backup being switched off
    /// is a choice, not a fault, and doesn't count.
    var needsAttention: Bool {
        switch status {
        case .locked: true
        case .ready: lastError != nil
        case .needsSetup, .unavailable: false
        }
    }

    /// Looks in the keychain again for a key that wasn't there at launch.
    ///
    /// iCloud Keychain doesn't deliver instantly. On a new phone the key can
    /// land seconds or minutes after first launch, and without this the app
    /// would have already decided it was locked and asked for a phrase the user
    /// never needed — then stayed that way until the next sign-in. Cheap enough
    /// to run on every foreground.
    func recheckKey() {
        guard status == .locked, !didDeliberatelyForget, let userID else { return }
        guard let key = KeyVault.dataKey(for: userID) else { return }
        dataKey = key
        status = .ready
        lastError = nil
    }

    // MARK: - Lifecycle

    /// Works out where this account stands. Called on sign-in and on launch.
    func refresh(for user: AuthUser?) async {
        guard let client, let user else {
            status = .unavailable
            dataKey = nil
            userID = nil
            return
        }
        userID = user.id
        didDeliberatelyForget = false

        // The keychain is the fast path and the one that makes a second device
        // seamless: if iCloud Keychain has already carried the key across,
        // there is nothing to ask the user for.
        if let key = KeyVault.dataKey(for: user.id) {
            dataKey = key
            status = .ready
            return
        }

        isWorking = true
        defer { isWorking = false }
        do {
            status = try await client.fetchKey(for: user.id) == nil ? .needsSetup : .locked
        } catch {
            // Offline is not the same as "no backup", and guessing wrong here
            // would show a first-run setup screen to someone who already has
            // years of entries — and then offer to overwrite their key.
            lastError = error as? BackupFailure ?? .network
            status = .unavailable
        }
    }

    // MARK: - Setting up

    /// Switches backup on. One tap, no ceremony, nothing for the user to save.
    ///
    /// A phrase *is* generated here, because the data key has to be wrapped
    /// under something before it can be stored — but it is never shown and
    /// never kept. That's deliberate: the key itself lives in the keychain and
    /// rides iCloud Keychain to the user's other devices, which covers the
    /// overwhelmingly common case without asking anyone to write down twelve
    /// words on day one to protect an empty journal.
    ///
    /// When the user does want a phrase, `regenerateRecoveryPhrase` mints one
    /// and rewraps the same key. Until then the stored wrapping is simply a
    /// recovery route nobody can walk — harmless, because nothing depends on it.
    func enable() async throws {
        guard let client else { throw BackupFailure.notConfigured }
        guard let userID else { throw BackupFailure.notSignedIn }
        guard status == .needsSetup else { throw BackupFailure.locked }

        isWorking = true
        defer { isWorking = false }

        let phrase = RecoveryPhrase.formatted(RecoveryPhrase.generate())
        guard let recovery = RecoveryPhrase.decode(phrase) else { throw BackupFailure.corruptData }

        let key = JournalCrypto.newDataKey()
        let salt = JournalCrypto.newSalt()
        let wrapped = try JournalCrypto.wrap(dataKey: key, recovery: recovery, salt: salt)

        // Upload before touching the keychain. If this throws we want the
        // device to stay in `needsSetup` rather than holding a key the server
        // has never heard of, which would look "ready" and upload entries
        // nothing could ever decrypt.
        try await client.storeKey(
            BackupClient.KeyRow(
                userID: userID,
                wrappedDEK: wrapped.base64EncodedString(),
                kdfSalt: salt.base64EncodedString()
            )
        )

        try KeyVault.store(key, for: userID)
        dataKey = key
        status = .ready
    }

    /// Issues a fresh recovery phrase for a backup this device can already
    /// read, for a phrase that was lost rather than compromised.
    ///
    /// The data key is deliberately unchanged — only its wrapping is replaced.
    /// Rotating the data key itself would mean re-encrypting and re-uploading
    /// every entry, and a failure halfway would leave the backup unreadable.
    /// The old phrase stops working the moment this succeeds.
    func regenerateRecoveryPhrase() async throws -> String {
        guard let client else { throw BackupFailure.notConfigured }
        guard let userID, let key = dataKey, status == .ready else {
            throw BackupFailure.locked
        }

        isWorking = true
        defer { isWorking = false }

        let phrase = RecoveryPhrase.formatted(RecoveryPhrase.generate())
        guard let recovery = RecoveryPhrase.decode(phrase) else { throw BackupFailure.corruptData }

        let salt = JournalCrypto.newSalt()
        let wrapped = try JournalCrypto.wrap(dataKey: key, recovery: recovery, salt: salt)

        try await client.replaceKeyWrapping(
            BackupClient.KeyRow(
                userID: userID,
                wrappedDEK: wrapped.base64EncodedString(),
                kdfSalt: salt.base64EncodedString()
            )
        )
        hasIssuedPhrase = true
        return phrase
    }

    // MARK: - Unlocking

    /// Trades a recovery phrase for the data key on a device that lacks it.
    func unlock(with input: String) async throws {
        guard let client else { throw BackupFailure.notConfigured }
        guard let userID else { throw BackupFailure.notSignedIn }
        guard let recovery = RecoveryPhrase.decode(input) else {
            throw BackupFailure.malformedRecoveryPhrase
        }

        isWorking = true
        defer { isWorking = false }

        guard let row = try await client.fetchKey(for: userID) else {
            throw BackupFailure.noKeyYet
        }
        guard
            let wrapped = Data(base64Encoded: row.wrappedDEK),
            let salt = Data(base64Encoded: row.kdfSalt)
        else { throw BackupFailure.corruptData }

        let key = try JournalCrypto.unwrap(wrapped: wrapped, recovery: recovery, salt: salt)
        try KeyVault.store(key, for: userID)
        dataKey = key
        status = .ready
        didDeliberatelyForget = false
    }

    /// The escape hatch for someone locked out for good: throws away the
    /// unreadable backup and starts a new one.
    ///
    /// This is destructive and cannot be undone — every entry already in the
    /// backup is deleted, because nothing on Earth can decrypt it once the
    /// phrase is gone. Anything still on *this* device survives and is
    /// re-uploaded under the new key by the sync that follows.
    ///
    /// Deliberately only available from `.locked`. From `.ready` the honest
    /// answer is `regenerateRecoveryPhrase`, which keeps the entries.
    func startOver() async throws -> String {
        guard let client else { throw BackupFailure.notConfigured }
        guard let userID else { throw BackupFailure.notSignedIn }
        guard status == .locked else { throw BackupFailure.noKeyYet }

        isWorking = true
        defer { isWorking = false }

        let phrase = RecoveryPhrase.formatted(RecoveryPhrase.generate())
        guard let recovery = RecoveryPhrase.decode(phrase) else { throw BackupFailure.corruptData }

        let key = JournalCrypto.newDataKey()
        let salt = JournalCrypto.newSalt()
        let wrapped = try JournalCrypto.wrap(dataKey: key, recovery: recovery, salt: salt)

        // Entries first. If this half succeeds we are left with no rows and the
        // old key, which is still `.locked` — recoverable by trying again. Doing
        // it the other way round would leave a new key alongside old ciphertext
        // it cannot read, which is the one state that breaks sync permanently.
        try await client.deleteAllEntries(for: userID)
        try await client.deleteSettings(for: userID)
        // Every row is gone, so any outstanding per-day deletions are moot —
        // and left behind they would go on hiding days from the next pull.
        pendingDeletions = []
        try await client.replaceKeyWrapping(
            BackupClient.KeyRow(
                userID: userID,
                wrappedDEK: wrapped.base64EncodedString(),
                kdfSalt: salt.base64EncodedString()
            )
        )

        try KeyVault.store(key, for: userID)
        dataKey = key
        status = .ready
        return phrase
    }

    // MARK: - Settings sync

    /// What this device last agreed with the server about, per user.
    ///
    /// Kept in UserDefaults rather than the payload because it describes *this
    /// install's* sync state, not the user's settings — restoring it onto a new
    /// phone would be meaningless.
    private struct SettingsSyncRecord {
        var fingerprint: String
        var syncedAt: Date

        static func load(for userID: String, from defaults: UserDefaults = .standard) -> SettingsSyncRecord? {
            guard let fingerprint = defaults.string(forKey: fingerprintKey(userID)),
                  let syncedAt = defaults.object(forKey: syncedAtKey(userID)) as? Date
            else { return nil }
            return SettingsSyncRecord(fingerprint: fingerprint, syncedAt: syncedAt)
        }

        func save(for userID: String, to defaults: UserDefaults = .standard) {
            defaults.set(fingerprint, forKey: Self.fingerprintKey(userID))
            defaults.set(syncedAt, forKey: Self.syncedAtKey(userID))
        }

        private static func fingerprintKey(_ userID: String) -> String {
            "backup.settings.fingerprint.\(userID)"
        }
        private static func syncedAtKey(_ userID: String) -> String {
            "backup.settings.syncedAt.\(userID)"
        }
    }

    /// Reconciles prompts and preferences.
    ///
    /// Direction is decided by comparing a content hash against what this device
    /// last synced, rather than by a modification timestamp — see
    /// `SettingsPayload.fingerprint`.
    ///
    /// The order of these branches matters more than it looks. A fresh install
    /// has default prompts and no sync record, and its snapshot will of course
    /// differ from the server's. Checking "have I ever synced?" *before*
    /// "have my settings changed?" is what stops a restore from pushing factory
    /// defaults over a lovingly rewritten prompt library.
    private func syncSettings(store: JournalStore, prefs: Preferences, key: SymmetricKey) async throws {
        guard let client, let userID else { return }

        let local = SettingsPayload(
            prompts: store.promptSnapshots(),
            settings: prefs.backupSnapshot,
            blocks: store.blockSnapshots()
        )
        let record = SettingsSyncRecord.load(for: userID)
        let remoteRow = try await client.fetchSettings(for: userID)

        func push() async throws {
            let sealed = try JournalCrypto.seal(
                SettingsPayload.encoder.encode(local), using: key
            )
            let now = Date.now
            try await client.uploadSettings(
                BackupClient.SettingsRow(
                    userID: userID,
                    ciphertext: sealed.base64EncodedString(),
                    updatedAt: PostgresTimestamp.string(from: now)
                )
            )
            SettingsSyncRecord(fingerprint: local.fingerprint, syncedAt: now).save(for: userID)
        }

        func pull(_ row: BackupClient.SettingsRow) throws {
            guard let blob = Data(base64Encoded: row.ciphertext),
                  let stamp = PostgresTimestamp.date(from: row.updatedAt)
            else { throw BackupFailure.corruptData }

            let payload = try SettingsPayload.decoder.decode(
                SettingsPayload.self, from: JournalCrypto.open(blob, using: key)
            )
            store.applyPrompts(payload.prompts, blocks: payload.blocks)
            prefs.apply(payload.settings)
            SettingsSyncRecord(fingerprint: payload.fingerprint, syncedAt: stamp).save(for: userID)
        }

        guard let remoteRow else {
            // Nothing up there yet — this device's setup becomes the backup.
            try await push()
            return
        }

        guard let record else {
            // This install has never synced settings, so it has nothing worth
            // defending. Whatever the account already has wins.
            try pull(remoteRow)
            return
        }

        if local.fingerprint != record.fingerprint {
            // Changed here since the last agreement. The device in the user's
            // hand wins; settings conflicts are rare and cheap to redo.
            try await push()
        } else if let stamp = PostgresTimestamp.date(from: remoteRow.updatedAt), stamp > record.syncedAt {
            try pull(remoteRow)
        }
    }

    // MARK: - Syncing

    /// Pulls anything newer from the server, then pushes anything newer here.
    ///
    /// Conflicts are settled per day by `updatedAt`, last write wins. That is
    /// the right call for a journal used on one phone at a time; it would not
    /// be for something genuinely concurrent.
    // MARK: - Deleted days

    /// Days the user deleted locally that the server may still hold.
    ///
    /// Kept on disk rather than in memory because the delete has to survive the
    /// request failing — offline, locked, or signed out. Until the row is gone
    /// from the server, `sync` would pull the day straight back down, so these
    /// are also what the pull skips over.
    private var pendingDeletions: Set<String> {
        get {
            guard let userID else { return [] }
            let stored = UserDefaults.standard.stringArray(forKey: Self.deletionsKey(userID))
            return Set(stored ?? [])
        }
        set {
            guard let userID else { return }
            let key = Self.deletionsKey(userID)
            if newValue.isEmpty {
                UserDefaults.standard.removeObject(forKey: key)
            } else {
                UserDefaults.standard.set(Array(newValue), forKey: key)
            }
        }
    }

    private static func deletionsKey(_ userID: String) -> String {
        "backup.deleted.days.\(userID)"
    }

    /// Tells backup that a day is gone for good, and tries to remove it from
    /// the server now. A failure here is not surfaced: the day is already gone
    /// from this device, and the next sync retries the removal.
    func forget(day: Date) {
        guard userID != nil else { return }
        pendingDeletions.insert(DayKey.string(from: day))
        Task { await flushDeletions() }
    }

    /// Sends every outstanding deletion, dropping each one only once the server
    /// has confirmed it.
    private func flushDeletions() async {
        guard let client, let userID else { return }
        var outstanding = pendingDeletions
        guard !outstanding.isEmpty else { return }

        for day in outstanding {
            do {
                try await client.deleteEntry(for: userID, day: day)
                outstanding.remove(day)
            } catch {
                // Leave this one and everything after it for the next sync.
                break
            }
        }
        pendingDeletions = outstanding
    }

    func sync(store: JournalStore, prefs: Preferences = .shared) async throws {
        guard let client else { throw BackupFailure.notConfigured }
        guard let userID, let key = dataKey, status == .ready else {
            throw BackupFailure.locked
        }
        guard !isWorking else { return }

        isWorking = true
        defer { isWorking = false }

        do {
            // Before anything else: a day the user deleted must not be fetched
            // back down while its row is still up there.
            await flushDeletions()
            let deleted = pendingDeletions

            let rows = try await client.fetchEntries(for: userID)

            // Pull
            var remoteStamps: [Date: Date] = [:]
            for row in rows {
                guard !deleted.contains(row.day) else { continue }
                guard
                    let day = DayKey.date(from: row.day),
                    let stamp = PostgresTimestamp.date(from: row.updatedAt)
                else { continue }
                remoteStamps[day] = stamp

                let local = store.entry(on: day)
                guard local == nil || local!.updatedAt < stamp else { continue }

                guard let blob = Data(base64Encoded: row.ciphertext) else {
                    throw BackupFailure.corruptData
                }
                let plaintext = try JournalCrypto.open(blob, using: key)
                let payload = try EntryPayload.decoder.decode(EntryPayload.self, from: plaintext)
                store.apply(payload, day: day, updatedAt: stamp)
            }

            // Push
            var uploads: [BackupClient.EntryRow] = []
            var pushed: [(JournalEntry, Date)] = []
            for entry in store.allEntries() {
                let day = store.day(for: entry.day)
                if let stamp = remoteStamps[day], stamp >= entry.updatedAt {
                    // Already current up there. Record that, or a day uploaded
                    // before this bookkeeping existed would count as pending
                    // forever — it is skipped here on every future sync too.
                    store.markBackedUp(entry, at: entry.updatedAt)
                    continue
                }

                let payload = store.snapshot(entry)
                let plaintext = try EntryPayload.encoder.encode(payload)
                let sealed = try JournalCrypto.seal(plaintext, using: key)
                uploads.append(
                    BackupClient.EntryRow(
                        userID: userID,
                        day: DayKey.string(from: day),
                        ciphertext: sealed.base64EncodedString(),
                        // The local stamp, not now(): it's what the next
                        // comparison on this device will be measured against.
                        updatedAt: PostgresTimestamp.string(from: entry.updatedAt)
                    )
                )
                pushed.append((entry, entry.updatedAt))
            }
            try await client.upload(uploads)
            // Only after the upload returns. Marking them before would claim a
            // day was safe when the request had yet to succeed.
            for (entry, version) in pushed { store.markBackedUp(entry, at: version) }
            store.save()

            // After entries, so a failure here can't stop the writing itself
            // from being backed up — settings are the less precious half.
            try await syncSettings(store: store, prefs: prefs, key: key)

            lastSyncedAt = .now
            lastError = nil
        } catch {
            let failure = error as? BackupFailure ?? .server(error.localizedDescription)
            lastError = failure
            throw failure
        }
    }

    // MARK: - Leaving

    /// Forgets the signed-in user, but deliberately **leaves the key in the
    /// keychain**.
    ///
    /// This used to delete it, which was wrong twice over. The item is stamped
    /// with the Supabase user id and lives in the user's own iCloud Keychain,
    /// so no one signing in under a different app account or a different Apple
    /// ID could ever read it — the deletion bought almost no protection. And
    /// because the item is synchronizable, deleting it propagated: signing out
    /// on one device stripped the key from every other device on the same Apple
    /// ID and left all of them demanding the phrase.
    ///
    /// Someone who genuinely wants the key gone — selling the phone, a shared
    /// device — asks for it explicitly via `forgetKeyOnThisDevice`.
    func signOut() {
        dataKey = nil
        userID = nil
        status = .unavailable
        lastSyncedAt = nil
        lastError = nil
        didDeliberatelyForget = false
    }

    /// Removes this device's copy of the key on purpose.
    ///
    /// Worth being precise about what this does and doesn't do: it disconnects
    /// this device from the backup. It does **not** make the local journal
    /// unreadable — entries live in plain SwiftData and are protected by iOS
    /// Data Protection, not by this key. So it is a sync control, not a privacy
    /// one, and the UI must not imply otherwise. Removing the local copy means
    /// deleting the app.
    ///
    /// The backup itself is untouched and the recovery phrase still opens it.
    /// Because the keychain item is synchronizable, this reaches the user's
    /// other devices too.
    func forgetKeyOnThisDevice() {
        guard let userID else { return }
        KeyVault.remove(for: userID)
        dataKey = nil
        // The backup still exists on the server; this device just can't read it.
        status = .locked
        lastSyncedAt = nil
        didDeliberatelyForget = true
    }
}
