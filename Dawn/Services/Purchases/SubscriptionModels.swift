import Foundation

/// One purchasable option, flattened from whatever the store hands back so the
/// paywall never has to know about RevenueCat types.
struct SubscriptionPlan: Identifiable, Equatable {
    let id: String
    /// "Annual", "Monthly", "Lifetime"
    let title: String
    /// Localised, store-formatted. Never build this from a raw number.
    let price: String
    /// "per year", "per month", "one time"
    let period: String
    /// Length in months, used only to order the cards. Nil for non-renewing.
    let periodMonths: Double?
    /// "$1.58 / month" — the framing that makes annual feel small.
    let equivalentMonthly: String?
    /// What the same period would cost at the monthly rate, shown struck
    /// through. The comparison is what makes the annual price feel small — a
    /// number on its own has nothing to be small against.
    let anchorPrice: String?
    /// "Save 62%"
    let savings: String?
    let trialDays: Int?
    let isRecommended: Bool

    var trialLabel: String? {
        guard let trialDays else { return nil }
        return "\(trialDays) days free"
    }
}

enum SubscriptionStatus: Equatable {
    case unknown
    case notSubscribed
    case subscribed(expires: Date?, willRenew: Bool, productID: String?)

    var isActive: Bool {
        if case .subscribed = self { return true }
        return false
    }
}

enum PurchaseFailure: LocalizedError, Equatable {
    case cancelled
    case pending
    case network
    case notAvailable
    case nothingToRestore
    case store(String)

    var errorDescription: String? {
        switch self {
        case .cancelled: nil // Silent: the user chose this.
        case .pending: "That purchase needs approval before it goes through."
        case .network: "Couldn't reach the App Store. Check your connection."
        case .notAvailable: "Subscriptions aren't available right now."
        case .nothingToRestore: "No previous purchase found on this Apple Account."
        case let .store(message): message
        }
    }
}
