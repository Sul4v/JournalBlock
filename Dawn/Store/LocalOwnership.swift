import Foundation

/// Remembers which account the journal on this device belongs to.
///
/// The local store has no owner of its own — entries belong to the phone, not
/// to an account — and signing out deliberately leaves them in place so the
/// same person signing back in finds their journal where they left it.
///
/// The hole that opens up is somebody *else* signing in on that phone: they'd
/// see the previous person's journal, and worse, turning on backup would
/// encrypt those entries under their key and upload them to their account for
/// good. This closes it by wiping when the account actually changes, while
/// leaving the same-user case untouched.
enum LocalOwnership {
    private static let key = "journal.localOwner"

    /// Hands the local journal to `userID`, clearing it first if it belonged to
    /// somebody else.
    ///
    /// A nil previous owner is treated as "ours" rather than "someone else's":
    /// that's an install from before this bookkeeping existed, and wiping a
    /// real user's journal to tidy up a missing key would be unforgivable.
    @MainActor
    static func claim(_ userID: String, store: JournalStore, prefs: Preferences) {
        let previous = UserDefaults.standard.string(forKey: key)
        UserDefaults.standard.set(userID, forKey: key)

        guard let previous, previous != userID else { return }
        store.wipeLocalJournal()
        prefs.clearPersonalDetails()
    }

    /// Called when an account is deleted, so the next person to sign in on this
    /// phone doesn't inherit a stale owner id.
    static func release() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}
