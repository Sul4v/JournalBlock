import Foundation
import Observation
import AuthenticationServices
import CryptoKit
import UIKit

/// The app's single source of truth for who is signed in.
///
/// Picks a provider once at launch: Supabase when keys are configured,
/// otherwise the local stand-in, so the flow is always exercisable.
@Observable
@MainActor
final class AuthController {
    private(set) var state: AuthState = .restoring
    /// Set while a network call is in flight, so buttons can show progress and
    /// double-taps can't fire two sign-ups.
    private(set) var isWorking = false
    /// Set when the user arrived via a password-reset link. The UI must clear
    /// this by setting a new password before letting them get on with anything.
    private(set) var needsNewPassword = false

    @ObservationIgnored private let provider: AuthProviding
    /// Retained between generating the nonce and Apple returning the token.
    @ObservationIgnored private var appleNonce: String?

    let usesLocalBackend: Bool

    init(provider: AuthProviding? = nil) {
        if let provider {
            self.provider = provider
            usesLocalBackend = false
        } else if let supabase = SupabaseAuthProvider() {
            self.provider = supabase
            usesLocalBackend = false
        } else {
            self.provider = LocalAuthProvider()
            usesLocalBackend = true
        }
    }

    var user: AuthUser? { state.user }
    var isSignedIn: Bool { state.isSignedIn }

    // MARK: - Lifecycle

    func restore() async {
        state = await provider.restoreSession()
    }

    // MARK: - Email

    /// Returns true when the account was created but is waiting on the emailed
    /// confirmation link — the caller should show the "check your inbox" state
    /// rather than treating it as an error.
    @discardableResult
    func signUp(email: String, password: String, confirmation: String) async throws -> Bool {
        if let failure = CredentialRules.validateEmail(email) { throw failure }
        if let failure = CredentialRules.validatePassword(password) { throw failure }
        guard password == confirmation else { throw AuthFailure.passwordsDontMatch }
        guard !isWorking else { return false }

        isWorking = true
        defer { isWorking = false }

        switch try await provider.signUp(email: email, password: password) {
        case let .signedIn(newState):
            state = newState
            return false
        case .needsEmailConfirmation:
            return true
        }
    }

    func resendConfirmation(to email: String) async throws {
        isWorking = true
        defer { isWorking = false }
        try await provider.resendConfirmation(to: email)
    }

    func signIn(email: String, password: String) async throws {
        if let failure = CredentialRules.validateEmail(email) { throw failure }
        guard !password.isEmpty else { throw AuthFailure.wrongCredentials }

        try await perform { try await $0.signIn(email: email, password: password) }
    }

    func sendPasswordReset(to email: String) async throws {
        if let failure = CredentialRules.validateEmail(email) { throw failure }
        isWorking = true
        defer { isWorking = false }
        try await provider.sendPasswordReset(to: email)
    }

    // MARK: - Apple

    /// Runs the Apple sheet from our own button.
    ///
    /// `SignInWithAppleButton` is the usual route, but it paints its own
    /// opaque capsule that can't take the glass material the Google and email
    /// buttons use, so the authorization controller is driven directly and the
    /// button beside it is ours.
    func signInWithApple() async throws {
        let request = ASAuthorizationAppleIDProvider().createRequest()
        prepareAppleRequest(request)

        let result: Result<ASAuthorization, Error>
        do {
            result = .success(try await AppleSignInPresenter.shared.authorize(request))
        } catch {
            result = .failure(error)
        }
        try await completeAppleSignIn(result)
    }

    /// Sets the scopes and the hashed nonce on an Apple request.
    func prepareAppleRequest(_ request: ASAuthorizationAppleIDRequest) {
        let nonce = Self.randomNonce()
        appleNonce = nonce
        request.requestedScopes = [.fullName, .email]
        request.nonce = Self.sha256(nonce)
    }

    /// Exchanges Apple's credential for a session.
    func completeAppleSignIn(_ result: Result<ASAuthorization, Error>) async throws {
        switch result {
        case let .success(authorization):
            guard
                let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                let tokenData = credential.identityToken,
                let idToken = String(data: tokenData, encoding: .utf8),
                let nonce = appleNonce
            else { throw AuthFailure.appleSignInFailed }

            let name = [credential.fullName?.givenName, credential.fullName?.familyName]
                .compactMap { $0 }
                .joined(separator: " ")

            try await perform {
                try await $0.signInWithApple(
                    idToken: idToken,
                    nonce: nonce,
                    fullName: name.isEmpty ? nil : name
                )
            }
            appleNonce = nil

        case let .failure(error):
            // The user tapping Cancel is not an error worth shouting about.
            if (error as NSError).code == ASAuthorizationError.canceled.rawValue { return }
            throw AuthFailure.appleSignInFailed
        }
    }

    // MARK: - Google

    /// True when the build has a client ID, or when we're on the local
    /// stand-in and can fake the round trip for review purposes.
    var canUseGoogle: Bool {
        GoogleSignInService.isConfigured || usesLocalBackend
    }

    func signInWithGoogle() async throws {
        guard !isWorking else { return }

        // Without a client ID there's nothing to present, so the stand-in
        // stands in for Google too and the flow stays walkable.
        guard GoogleSignInService.isConfigured else {
            guard usesLocalBackend else { throw AuthFailure.server(
                GoogleSignInService.Failure.notConfigured.errorDescription ?? "Google sign-in is unavailable."
            ) }
            try await perform {
                try await $0.signInWithGoogle(
                    idToken: "local-google-demo",
                    accessToken: "local",
                    nonce: "local",
                    fullName: nil
                )
            }
            return
        }

        do {
            let result = try await GoogleSignInService.signIn()
            try await perform {
                try await $0.signInWithGoogle(
                    idToken: result.idToken,
                    accessToken: result.accessToken,
                    nonce: result.nonce,
                    fullName: result.fullName
                )
            }
        } catch let failure as GoogleSignInService.Failure {
            // Cancellation is silent, same as Apple's.
            if case .cancelled = failure { return }
            throw AuthFailure.server(failure.errorDescription ?? "Google sign-in failed.")
        }
    }

    // MARK: - Emailed links

    /// Called from `onOpenURL`. Returns true if the URL was ours.
    @discardableResult
    func handleCallback(_ url: URL) async -> Bool {
        do {
            guard let callback = try await provider.handleCallback(url) else { return false }
            switch callback {
            case let .signedIn(newState):
                state = newState
                needsNewPassword = false
            case let .passwordRecovery(newState):
                state = newState
                needsNewPassword = true
            }
            return true
        } catch {
            return false
        }
    }

    func updatePassword(_ password: String) async throws {
        if let failure = CredentialRules.validatePassword(password) { throw failure }
        isWorking = true
        defer { isWorking = false }
        try await provider.updatePassword(password)
        needsNewPassword = false
    }

    // MARK: - Leaving

    func signOut() async {
        try? await provider.signOut()
        state = .signedOut
        needsNewPassword = false
    }

    func deleteAccount() async throws {
        isWorking = true
        defer { isWorking = false }
        try await provider.deleteAccount()
        state = .signedOut
    }

    // MARK: - Plumbing

    private func perform(_ work: (AuthProviding) async throws -> AuthState) async throws {
        guard !isWorking else { return }
        isWorking = true
        defer { isWorking = false }
        state = try await work(provider)
    }

    // MARK: - Nonce

    private static func randomNonce(length: Int = 32) -> String {
        let charset = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        var remaining = length
        while remaining > 0 {
            var random: UInt8 = 0
            let status = SecRandomCopyBytes(kSecRandomDefault, 1, &random)
            guard status == errSecSuccess else { continue }
            // Reject values that would bias the modulo.
            if random < charset.count * (255 / charset.count) {
                result.append(charset[Int(random) % charset.count])
                remaining -= 1
            }
        }
        return result
    }

    private static func sha256(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }
}

// MARK: - Apple sheet

/// Bridges `ASAuthorizationController`'s delegate callbacks into `async`.
///
/// A single shared instance because the controller only retains its delegate
/// weakly — a per-call object would be deallocated before Apple answered.
@MainActor
private final class AppleSignInPresenter: NSObject {
    static let shared = AppleSignInPresenter()

    private var continuation: CheckedContinuation<ASAuthorization, Error>?

    func authorize(_ request: ASAuthorizationAppleIDRequest) async throws -> ASAuthorization {
        // One sheet at a time. The buttons are disabled while a sign-in is in
        // flight, so this only guards against a race we'd rather not resume
        // a continuation twice for.
        guard continuation == nil else { throw AuthFailure.appleSignInFailed }

        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            let controller = ASAuthorizationController(authorizationRequests: [request])
            controller.delegate = self
            controller.presentationContextProvider = self
            controller.performRequests()
        }
    }

    private func finish(_ result: Result<ASAuthorization, Error>) {
        let pending = continuation
        continuation = nil
        pending?.resume(with: result)
    }
}

extension AppleSignInPresenter: ASAuthorizationControllerDelegate {
    // Apple delivers these on the main queue.
    nonisolated func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        MainActor.assumeIsolated { finish(.success(authorization)) }
    }

    nonisolated func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithError error: Error
    ) {
        MainActor.assumeIsolated { finish(.failure(error)) }
    }
}

extension AppleSignInPresenter: ASAuthorizationControllerPresentationContextProviding {
    nonisolated func presentationAnchor(
        for controller: ASAuthorizationController
    ) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap(\.windows)
                .first { $0.isKeyWindow } ?? ASPresentationAnchor()
        }
    }
}
