import Foundation

/// Backend keys and product identifiers.
///
/// Both keys below are *publishable* client keys — the Supabase anon key is
/// protected by Row Level Security, and the RevenueCat key is a public SDK key.
/// Neither is a secret, but neither should be a service-role or secret key.
///
/// Until they're filled in, Dawn runs against in-memory stand-ins so the whole
/// flow is testable end to end. See `README.md` → "Going live".
enum AppConfig {

    /// The product name, everywhere the user can see it. One definition so a
    /// rename is one line rather than a hunt through twenty views.
    static let appName = "JournalBlock"

    /// The paid tier, as users see it. The RevenueCat entitlement below is a
    /// separate internal identifier and does not have to match.
    static let tierName = "Pro"

    // MARK: - Supabase

    /// e.g. "https://abcdefghijklm.supabase.co"
    static let supabaseURL = "https://gexgiqsqtbwxkzbjowdp.supabase.co"
    /// The `anon` / `publishable` key from Project Settings → API.
    static let supabaseAnonKey = "sb_publishable_OqGjl5CzkjrW5PdQCAe-xg_aq8foerL"

    /// Where Supabase's emailed links come back to. This exact string must
    /// also be listed under Authentication → URL Configuration → Redirect URLs,
    /// or Supabase refuses to redirect and the link dead-ends in a browser.
    static let authCallbackURL = URL(string: "journalblock://auth-callback")!

    // MARK: - Google

    /// The iOS OAuth client ID from the Google Cloud console, e.g.
    /// "1234567890-abc123.apps.googleusercontent.com".
    ///
    /// The matching REVERSED_CLIENT_ID must also go into `CFBundleURLSchemes`
    /// in `project.yml` — Google's callback can't reach the app without it.
    static let googleClientID = "552894245808-p0rl1uptn42343j14mrpmh5uacmgeuea.apps.googleusercontent.com"

    /// Only needed if your Supabase Google provider is configured against a web
    /// client ID rather than the iOS one. Leave empty otherwise.
    static let googleServerClientID = ""

    // MARK: - RevenueCat

    /// The **public** Apple SDK key from RevenueCat → API keys (starts `appl_`).
    static let revenueCatAPIKey = "appl_HqpMTTWkderCYwaXpEUajSbjPfS"

    /// The entitlement identifier configured in RevenueCat that unlocks Dawn.
    static let entitlementID = "journalblock_pro"
    /// The offering to show on the paywall. Empty string = the current default.
    static let offeringID = ""

    // MARK: - Legal (required on the paywall by App Review)

    /// TODO: both of these must resolve before submission. A dead Terms link on
    /// a subscription paywall is a reliable rejection (Guideline 3.1.2).
    static let termsURL = URL(string: "https://dawn.app/terms")!
    static let privacyURL = URL(string: "https://dawn.app/privacy")!
    static let supportEmail = "support@dawn.app"

    /// True once `SocialProof.quotes` holds real, attributable reviews.
    ///
    /// Off by design. The paywall and the onboarding proof card previously
    /// showed an invented "4.8 · App Store" rating and two named reviewers for
    /// an app that has never shipped — Guideline 2.3.1, and a straightforward
    /// misrepresentation besides. Both screens now render nothing rather than
    /// something false. Flip this when the quotes below are genuine.
    static let showsSocialProof = false

    enum SocialProof {
        /// Replace with real reviews before enabling `showsSocialProof`.
        static let quotes: [(text: String, name: String)] = []

        /// The App Store's own rating must never be redrawn inside the app —
        /// use `requestReview` instead. Left as nil deliberately.
        static let ratingLine: String? = nil
    }

    // MARK: - Derived

    static var hasSupabase: Bool {
        !supabaseURL.isEmpty && !supabaseAnonKey.isEmpty && URL(string: supabaseURL) != nil
    }

    static var hasRevenueCat: Bool {
        revenueCatAPIKey.hasPrefix("appl_")
    }

    static var hasGoogle: Bool {
        googleClientID.hasSuffix(".apps.googleusercontent.com")
    }

    /// True when either backend is missing, i.e. we're running on stand-ins.
    static var isRunningLocally: Bool { !hasSupabase || !hasRevenueCat }
}
