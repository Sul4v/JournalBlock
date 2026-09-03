import Foundation

/// A real-feeling auth backend that lives entirely on the device.
///
/// This exists so the sign-up flow, paywall, and account screens can be built,
/// demoed, and QA'd before Supabase keys are in place — and so the app never
/// hard-fails when it can't reach a network. It stores a salted hash rather
/// than the password itself; it is still not a security boundary, and
/// `AppConfig.hasSupabase` switches it off the moment real keys exist.
final class LocalAuthProvider: AuthProviding {
    private let defaults: UserDefaults
    private let latency: Duration

    init(defaults: UserDefaults = .standard, latency: Duration = .milliseconds(650)) {
        self.defaults = defaults
        self.latency = latency
    }

    // MARK: - Session

    func restoreSession() async -> AuthState {
        guard let id = defaults.string(forKey: Key.sessionUserID),
              let user = storedUser(id: id) else { return .signedOut }
        return .signedIn(user)
    }

    func signUp(email: String, password: String) async throws -> SignUpOutcome {
        try await simulateWork()
        let email = email.trimmed.lowercased()
        if accounts()[email] != nil { throw AuthFailure.emailAlreadyRegistered }

        let user = AuthUser(
            id: UUID().uuidString,
            email: email,
            createdAt: .now,
            displayName: nil
        )
        var all = accounts()
        all[email] = StoredAccount(
            id: user.id,
            email: email,
            passwordHash: Self.hash(password, salt: user.id),
            createdAt: user.createdAt,
            displayName: nil
        )
        save(all)
        defaults.set(user.id, forKey: Key.sessionUserID)
        return .signedIn(.signedIn(user))
    }

    func resendConfirmation(to email: String) async throws {
        try await simulateWork()
    }

    func signIn(email: String, password: String) async throws -> AuthState {
        try await simulateWork()
        let email = email.trimmed.lowercased()
        guard let account = accounts()[email],
              account.passwordHash == Self.hash(password, salt: account.id)
        else { throw AuthFailure.wrongCredentials }

        defaults.set(account.id, forKey: Key.sessionUserID)
        return .signedIn(account.asUser)
    }

    func signInWithApple(idToken: String, nonce: String, fullName: String?) async throws -> AuthState {
        try await simulateWork()
        // Stand-in: key the local account off the token so repeat sign-ins
        // land on the same user.
        let email = "apple-\(idToken.prefix(8))@privaterelay.local"
        if let existing = accounts()[email] {
            defaults.set(existing.id, forKey: Key.sessionUserID)
            return .signedIn(existing.asUser)
        }
        var state = try await signedInState(email: email)
        if let name = fullName, !name.trimmed.isEmpty, var user = state.user {
            user.displayName = name
            updateDisplayName(name, for: user)
            state = .signedIn(user)
        }
        return state
    }

    func signInWithGoogle(idToken: String, accessToken: String, nonce: String, fullName: String?) async throws -> AuthState {
        try await simulateWork()
        let email = "google-\(idToken.prefix(8))@example.local"
        if let existing = accounts()[email] {
            defaults.set(existing.id, forKey: Key.sessionUserID)
            return .signedIn(existing.asUser)
        }
        var state = try await signedInState(email: email)
        if let fullName, !fullName.trimmed.isEmpty, var user = state.user {
            user.displayName = fullName
            updateDisplayName(fullName, for: user)
            state = .signedIn(user)
        }
        return state
    }

    func sendPasswordReset(to email: String) async throws {
        try await simulateWork()
        // Nothing to send locally; the UI still shows the same confirmation so
        // the flow can be reviewed.
    }

    func signOut() async throws {
        defaults.removeObject(forKey: Key.sessionUserID)
    }

    func handleCallback(_ url: URL) async throws -> AuthCallback? { nil }

    func updatePassword(_ password: String) async throws {
        try await simulateWork()
    }

    func deleteAccount() async throws {
        try await simulateWork()
        guard let id = defaults.string(forKey: Key.sessionUserID) else { throw AuthFailure.notSignedIn }
        var all = accounts()
        all = all.filter { $0.value.id != id }
        save(all)
        defaults.removeObject(forKey: Key.sessionUserID)
    }

    /// Social sign-in never waits on confirmation, so unwrap to a session.
    private func signedInState(email: String) async throws -> AuthState {
        guard case let .signedIn(state) = try await signUp(
            email: email, password: UUID().uuidString
        ) else { throw AuthFailure.appleSignInFailed }
        return state
    }

    // MARK: - Storage

    private struct StoredAccount: Codable {
        let id: String
        let email: String
        let passwordHash: String
        let createdAt: Date
        var displayName: String?

        var asUser: AuthUser {
            AuthUser(id: id, email: email, createdAt: createdAt, displayName: displayName)
        }
    }

    private func accounts() -> [String: StoredAccount] {
        guard let data = defaults.data(forKey: Key.accounts),
              let decoded = try? JSONDecoder().decode([String: StoredAccount].self, from: data)
        else { return [:] }
        return decoded
    }

    private func save(_ accounts: [String: StoredAccount]) {
        guard let data = try? JSONEncoder().encode(accounts) else { return }
        defaults.set(data, forKey: Key.accounts)
    }

    private func storedUser(id: String) -> AuthUser? {
        accounts().values.first { $0.id == id }?.asUser
    }

    private func updateDisplayName(_ name: String, for user: AuthUser) {
        var all = accounts()
        guard var account = all[user.email] else { return }
        account.displayName = name
        all[user.email] = account
        save(all)
    }

    private func simulateWork() async throws {
        // Real latency matters: buttons that resolve instantly hide every
        // loading state, and those states are where sign-up flows break.
        try? await Task.sleep(for: latency)
    }

    private static func hash(_ password: String, salt: String) -> String {
        var hasher = Hasher()
        hasher.combine(password)
        hasher.combine(salt)
        return String(hasher.finalize())
    }

    private enum Key {
        static let accounts = "dawn.local.accounts"
        static let sessionUserID = "dawn.local.session"
    }
}
