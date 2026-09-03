import Foundation

/// Everything that can go wrong between the journal and the backup.
enum BackupFailure: LocalizedError, Equatable {
    case notConfigured
    case notSignedIn
    /// No key has been set up for this account yet.
    case noKeyYet
    /// The account has a backup, but this device can't unlock it without the
    /// recovery phrase.
    case locked
    case wrongRecoveryPhrase
    case malformedRecoveryPhrase
    case corruptData
    case keychain(OSStatus)
    case network
    case server(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Backup isn't available in this build."
        case .notSignedIn:
            return "Sign in to back up your journal."
        case .noKeyYet:
            return "This account doesn't have a backup yet."
        case .locked:
            return "Enter your recovery phrase to unlock your backup."
        case .wrongRecoveryPhrase:
            return "That recovery phrase doesn't match this account."
        case .malformedRecoveryPhrase:
            return "A recovery phrase is 12 words."
        case .corruptData:
            return "Some backed-up writing couldn't be read."
        case .keychain:
            return "This device wouldn't let us store your key."
        case .network:
            return "You appear to be offline."
        case let .server(message):
            return message
        }
    }
}
