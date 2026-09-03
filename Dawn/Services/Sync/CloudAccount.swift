import Foundation

/// Whether this device is signed into iCloud.
///
/// What we actually want to know is whether iCloud Keychain is switched on,
/// because that's what carries the backup key to a new phone. There is no
/// public API for that. This is the reliable half of the answer: no iCloud
/// account means no iCloud Keychain, full stop.
///
/// The reverse doesn't hold — someone can be signed into iCloud with Keychain
/// switched off — so treat `true` as "probably fine" and `false` as "definitely
/// needs a recovery phrase". The backstops for the gap are the foreground key
/// re-check and the "Get a phrase" button, which stay available to everyone.
///
/// Verified on device: this returns a token even though the app carries no
/// iCloud entitlement. Worth re-checking if that ever appears to change, since
/// a nil here would wrongly tell every user they have no iCloud.
enum CloudAccount {
    static var isSignedIn: Bool {
        FileManager.default.ubiquityIdentityToken != nil
    }
}
