import Foundation

/// What Dawn needs from an identity backend. Supabase implements this for
/// production; `LocalAuthProvider` implements it so the whole flow runs before
/// any keys are configured.
protocol AuthProviding: AnyObject {
    /// Restores a persisted session on launch. Returns `.signedOut` if none.
    func restoreSession() async -> AuthState

    /// Sign-up does not always produce a session: with email confirmation on,
    /// the account exists but stays dormant until the link is clicked.
    func signUp(email: String, password: String) async throws -> SignUpOutcome
    func signIn(email: String, password: String) async throws -> AuthState

    /// `idToken` and `nonce` come from `ASAuthorizationAppleIDCredential`.
    func signInWithApple(idToken: String, nonce: String, fullName: String?) async throws -> AuthState

    /// `idToken` comes from `GoogleSignInService`.
    func signInWithGoogle(idToken: String, accessToken: String, nonce: String, fullName: String?) async throws -> AuthState

    /// Sends the confirmation email again. Succeeds whether or not the address
    /// is registered, so it can't be used to probe for accounts.
    func resendConfirmation(to email: String) async throws

    func sendPasswordReset(to email: String) async throws
    func signOut() async throws

    /// Completes a sign-in from an emailed link (confirmation or recovery).
    /// Returns nil when the URL isn't one of ours.
    func handleCallback(_ url: URL) async throws -> AuthCallback?

    /// Sets a new password for the signed-in user.
    func updatePassword(_ password: String) async throws

    /// Permanently removes the account and any server-side data.
    func deleteAccount() async throws
}


/// What happened at the end of a sign-up.
enum SignUpOutcome {
    case signedIn(AuthState)
    /// The account was created but needs the emailed link before it can be used.
    case needsEmailConfirmation(email: String)
}


/// What an emailed link turned out to be.
enum AuthCallback {
    case signedIn(AuthState)
    /// A password-reset link. The user now has a session, but should be asked
    /// to set a new password before going anywhere else.
    case passwordRecovery(AuthState)
}
