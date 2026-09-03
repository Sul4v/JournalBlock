import Foundation

/// The signed-in person. Deliberately thin — Dawn's journal data is local, so
/// the account exists to carry the subscription and to sync later.
struct AuthUser: Equatable, Identifiable {
    let id: String
    let email: String
    let createdAt: Date
    var displayName: String?

    var initials: String {
        let source = displayName?.trimmed.isEmpty == false ? displayName! : email
        let letters = source.split(separator: " ").prefix(2).compactMap(\.first)
        return letters.isEmpty ? "·" : String(letters).uppercased()
    }
}

enum AuthState: Equatable {
    /// Before the first session restore completes. The UI holds still here
    /// rather than flashing the sign-in screen at a returning user.
    case restoring
    case signedOut
    case signedIn(AuthUser)

    var user: AuthUser? {
        if case let .signedIn(user) = self { return user }
        return nil
    }

    var isSignedIn: Bool { user != nil }
}

/// Errors phrased for a person, not a log file. Every message says what to do
/// next — vague auth errors are a measurable drop-off point.
enum AuthFailure: LocalizedError, Equatable {
    case invalidEmail
    case weakPassword(minimum: Int)
    case passwordsDontMatch
    case wrongCredentials
    case emailAlreadyRegistered
    case emailNotConfirmed
    case rateLimited
    case emailRateLimited
    case network
    case appleSignInFailed
    case notSignedIn
    case server(String)

    var errorDescription: String? {
        switch self {
        case .invalidEmail:
            "That doesn't look like an email address."
        case let .weakPassword(minimum):
            "Passwords need at least \(minimum) characters."
        case .passwordsDontMatch:
            "Those two passwords don't match."
        case .wrongCredentials:
            "That email and password don't match. Try again, or reset your password."
        case .emailAlreadyRegistered:
            "There's already an account with that email. Sign in instead?"
        case .emailNotConfirmed:
            "Check your inbox and confirm your email first."
        case .rateLimited:
            "Too many attempts. Give it a minute."
        case .emailRateLimited:
            // Deliberately not "a minute" — the sending limit is hourly, and a
            // wrong number here just makes the user tap again and fail again.
            "We've sent too many emails recently. Try again in an hour."
        case .network:
            "Couldn't reach the server. Check your connection."
        case .appleSignInFailed:
            "Apple sign-in didn't complete. Try again or use email."
        case .notSignedIn:
            "You're not signed in."
        case let .server(message):
            message
        }
    }
}

/// The one place that decides what counts as a valid credential, so the sign-up
/// form, the sign-in form, and the backend can't disagree.
enum CredentialRules {
    static let minimumPasswordLength = 8

    static func validateEmail(_ email: String) -> AuthFailure? {
        let trimmed = email.trimmed
        // Deliberately permissive: the server is the real authority, and
        // over-strict client regexes reject valid addresses.
        let looksLikeEmail = trimmed.contains("@")
            && trimmed.split(separator: "@").count == 2
            && trimmed.split(separator: "@").last?.contains(".") == true
            && !trimmed.hasSuffix(".")
        return looksLikeEmail ? nil : .invalidEmail
    }

    static func validatePassword(_ password: String) -> AuthFailure? {
        password.count >= minimumPasswordLength
            ? nil
            : .weakPassword(minimum: minimumPasswordLength)
    }

    /// 0...1, drives the strength meter on the sign-up form.
    static func strength(of password: String) -> Double {
        guard !password.isEmpty else { return 0 }
        var score = 0.0
        if password.count >= minimumPasswordLength { score += 0.4 }
        if password.count >= 12 { score += 0.2 }
        if password.rangeOfCharacter(from: .decimalDigits) != nil { score += 0.15 }
        if password.rangeOfCharacter(from: .uppercaseLetters) != nil { score += 0.15 }
        if password.rangeOfCharacter(from: CharacterSet.alphanumerics.inverted) != nil { score += 0.1 }
        return min(1, score)
    }

    static func strengthLabel(_ score: Double) -> String {
        switch score {
        case ..<0.4: "Too short"
        case ..<0.7: "Okay"
        case ..<0.9: "Good"
        default: "Strong"
        }
    }
}
