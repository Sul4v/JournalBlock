import Foundation
import Supabase

/// Production identity, backed by Supabase Auth.
///
/// Errors are mapped by inspecting the message rather than matching the SDK's
/// error enum, so a Supabase point release can't silently turn a friendly
/// message back into a stack trace.
final class SupabaseAuthProvider: AuthProviding {
    private let client: SupabaseClient

    /// Fails when the build has no Supabase keys configured, which is what
    /// makes `AuthController` fall back to the local stand-in.
    ///
    /// The client is shared with the backup layer via `SupabaseStack` so both
    /// speak to Postgres as the same signed-in user. See that type for why.
    init?(client: SupabaseClient? = SupabaseStack.shared) {
        guard let client else { return nil }
        self.client = client
    }

    // MARK: - Session

    func restoreSession() async -> AuthState {
        do {
            let session = try await client.auth.session
            return .signedIn(Self.user(from: session.user))
        } catch {
            return .signedOut
        }
    }

    func signUp(email: String, password: String) async throws -> SignUpOutcome {
        let address = email.trimmed.lowercased()
        do {
            let response = try await client.auth.signUp(
                email: address,
                password: password,
                redirectTo: AppConfig.authCallbackURL
            )
            // A nil session means the project requires email confirmation. That
            // is a normal outcome, not a failure — the account does exist.
            guard response.session != nil else {
                return .needsEmailConfirmation(email: address)
            }
            return .signedIn(.signedIn(Self.user(from: response.user)))
        } catch {
            throw Self.mapped(error)
        }
    }

    func resendConfirmation(to email: String) async throws {
        do {
            try await client.auth.resend(
                email: email.trimmed.lowercased(),
                type: .signup,
                emailRedirectTo: AppConfig.authCallbackURL
            )
        } catch {
            throw Self.mapped(error)
        }
    }

    func signIn(email: String, password: String) async throws -> AuthState {
        do {
            let session = try await client.auth.signIn(
                email: email.trimmed.lowercased(),
                password: password
            )
            return .signedIn(Self.user(from: session.user))
        } catch {
            throw Self.mapped(error)
        }
    }

    func signInWithApple(idToken: String, nonce: String, fullName: String?) async throws -> AuthState {
        do {
            let session = try await client.auth.signInWithIdToken(
                credentials: .init(provider: .apple, idToken: idToken, nonce: nonce)
            )
            var user = Self.user(from: session.user)
            // Apple only sends the name on the very first authorization, so
            // persist it the moment we see it or it's gone for good.
            if let fullName, !fullName.trimmed.isEmpty, user.displayName == nil {
                user.displayName = fullName
                try? await client.auth.update(user: UserAttributes(data: ["full_name": .string(fullName)]))
            }
            return .signedIn(user)
        } catch {
            throw Self.mapped(error)
        }
    }

    func signInWithGoogle(idToken: String, accessToken: String, nonce: String, fullName: String?) async throws -> AuthState {
        do {
            let session = try await client.auth.signInWithIdToken(
                credentials: .init(
                    provider: .google,
                    idToken: idToken,
                    accessToken: accessToken,
                    nonce: nonce
                )
            )
            var user = Self.user(from: session.user)
            if let fullName, !fullName.trimmed.isEmpty, user.displayName == nil {
                user.displayName = fullName
                try? await client.auth.update(user: UserAttributes(data: ["full_name": .string(fullName)]))
            }
            return .signedIn(user)
        } catch {
            throw Self.mapped(error)
        }
    }

    func sendPasswordReset(to email: String) async throws {
        do {
            try await client.auth.resetPasswordForEmail(
                email.trimmed.lowercased(),
                redirectTo: AppConfig.authCallbackURL
            )
        } catch {
            throw Self.mapped(error)
        }
    }

    func signOut() async throws {
        do {
            try await client.auth.signOut()
        } catch {
            throw Self.mapped(error)
        }
    }

    /// Calls the `delete_account` Postgres function, which runs as
    /// `security definer` and removes the caller's auth row plus their data.
    /// The client SDK can't delete users directly — that needs a service key,
    /// which must never ship in an app. See `supabase/schema.sql`.
    func deleteAccount() async throws {
        do {
            try await client.rpc("delete_account").execute()
            try? await client.auth.signOut()
        } catch {
            throw Self.mapped(error)
        }
    }

    // MARK: - Emailed links

    func handleCallback(_ url: URL) async throws -> AuthCallback? {
        guard url.scheme == AppConfig.authCallbackURL.scheme else { return nil }
        do {
            let session = try await client.auth.session(from: url)
            let state = AuthState.signedIn(Self.user(from: session.user))
            // A recovery link carries the user in, but they still owe us a new
            // password — the caller decides what to show.
            return Self.isRecovery(url) ? .passwordRecovery(state) : .signedIn(state)
        } catch {
            throw Self.mapped(error)
        }
    }

    func updatePassword(_ password: String) async throws {
        do {
            _ = try await client.auth.update(user: UserAttributes(password: password))
        } catch {
            throw Self.mapped(error)
        }
    }

    /// Supabase marks the link type in the query or the URL fragment depending
    /// on whether the project is on PKCE or implicit flow, so check both.
    private static func isRecovery(_ url: URL) -> Bool {
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let query = components?.queryItems?.first { $0.name == "type" }?.value
        let fragment = components?.fragment ?? ""
        return query == "recovery" || fragment.contains("type=recovery")
    }

    // MARK: - Mapping

    private static func user(from user: User) -> AuthUser {
        let name = user.userMetadata["full_name"]?.stringValue
        return AuthUser(
            id: user.id.uuidString,
            email: user.email ?? "",
            createdAt: user.createdAt,
            displayName: name
        )
    }

    private static func mapped(_ error: Error) -> AuthFailure {
        if let failure = error as? AuthFailure { return failure }

        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain { return .network }

        let text = error.localizedDescription.lowercased()
        switch true {
        case text.contains("already registered"),
             text.contains("already been registered"),
             text.contains("user already exists"):
            return .emailAlreadyRegistered
        case text.contains("invalid login"), text.contains("invalid credentials"):
            return .wrongCredentials
        case text.contains("email not confirmed"), text.contains("not confirmed"):
            return .emailNotConfirmed
        // The email sending cap and the auth attempt cap are different
        // limits with different windows, so they can't share a message.
        case text.contains("email rate limit"),
             text.contains("over_email_send_rate_limit"):
            return .emailRateLimited
        case text.contains("rate limit"), text.contains("too many"):
            return .rateLimited
        case text.contains("password"):
            return .weakPassword(minimum: CredentialRules.minimumPasswordLength)
        case text.contains("network"), text.contains("offline"), text.contains("connection"):
            return .network
        default:
            return .server(error.localizedDescription)
        }
    }
}
