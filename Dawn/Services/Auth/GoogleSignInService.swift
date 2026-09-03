import Foundation
import UIKit
import GoogleSignIn

/// Presents Google's native sign-in sheet and hands back the ID token that
/// Supabase exchanges for a session.
///
/// Native rather than a web redirect: it reuses the Google session already on
/// the device, so for most people it's one tap instead of a password.
enum GoogleSignInService {

    struct Result {
        let idToken: String
        let accessToken: String
        let fullName: String?
        /// The raw nonce this token was minted against. Supabase re-checks it
        /// against the token's `nonce` claim, which is what stops a stolen
        /// token being replayed into our project.
        let nonce: String
    }

    enum Failure: LocalizedError {
        case notConfigured
        case cancelled
        case noPresenter
        case missingIDToken
        case underlying(String)

        var errorDescription: String? {
            switch self {
            case .notConfigured:
                "Google sign-in isn't configured in this build yet."
            case .cancelled:
                nil
            case .noPresenter:
                "Couldn't open Google sign-in."
            case .missingIDToken:
                "Google didn't return a usable token. Try again."
            case let .underlying(message):
                message
            }
        }
    }

    static var isConfigured: Bool { AppConfig.hasGoogle }

    /// Call once at launch. Safe to call when no client ID is set.
    static func configure() {
        guard isConfigured else { return }
        GIDSignIn.sharedInstance.configuration = GIDConfiguration(
            clientID: AppConfig.googleClientID,
            serverClientID: AppConfig.googleServerClientID.isEmpty
                ? nil
                : AppConfig.googleServerClientID
        )
    }

    /// Forwards the OAuth callback. Wired up in `DawnApp` via `onOpenURL`.
    @discardableResult
    static func handle(_ url: URL) -> Bool {
        guard isConfigured else { return false }
        return GIDSignIn.sharedInstance.handle(url)
    }

    @MainActor
    static func signIn() async throws -> Result {
        guard isConfigured else { throw Failure.notConfigured }
        guard let presenter = topViewController() else { throw Failure.noPresenter }

        // Unlike Apple, Google embeds the nonce verbatim rather than hashing
        // it, so the same random string goes to Google and to Supabase.
        let nonce = Self.randomNonce()

        do {
            let result = try await GIDSignIn.sharedInstance.signIn(
                withPresenting: presenter,
                hint: nil,
                additionalScopes: nil,
                nonce: nonce
            )
            guard let idToken = result.user.idToken?.tokenString else {
                throw Failure.missingIDToken
            }
            let profile = result.user.profile
            return Result(
                idToken: idToken,
                accessToken: result.user.accessToken.tokenString,
                fullName: profile?.name,
                nonce: nonce
            )
        } catch let error as Failure {
            throw error
        } catch {
            // Tapping Cancel is a choice, not an error worth surfacing.
            if (error as NSError).code == GIDSignInError.canceled.rawValue {
                throw Failure.cancelled
            }
            throw Failure.underlying(error.localizedDescription)
        }
    }

    private static func randomNonce(length: Int = 32) -> String {
        let charset = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        var remaining = length
        while remaining > 0 {
            var byte: UInt8 = 0
            guard SecRandomCopyBytes(kSecRandomDefault, 1, &byte) == errSecSuccess else { continue }
            // Reject values that would bias the modulo.
            if byte < charset.count * (255 / charset.count) {
                result.append(charset[Int(byte) % charset.count])
                remaining -= 1
            }
        }
        return result
    }

    @MainActor
    private static func topViewController() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }

        var controller = scene?.windows.first(where: \.isKeyWindow)?.rootViewController
        while let presented = controller?.presentedViewController {
            controller = presented
        }
        return controller
    }
}
