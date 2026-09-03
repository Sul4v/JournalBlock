import Foundation

/// Stand-in store used until a RevenueCat key is configured.
///
/// It presents the same plan shapes the real paywall will show, and a purchase
/// flips a local flag — enough to walk the full funnel, review the copy, and
/// test the gate without StoreKit configuration.
final class LocalPurchaseProvider: PurchaseProviding {
    private let defaults: UserDefaults
    private var userID: String?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func identify(userID: String) async { self.userID = userID }
    func signOut() async { userID = nil }

    func loadPlans() async throws -> [SubscriptionPlan] {
        try? await Task.sleep(for: .milliseconds(500))
        return [
            SubscriptionPlan(
                id: "dawn.annual",
                title: "Annual",
                price: "$56.99",
                period: "per year",
                periodMonths: 12,
                equivalentMonthly: "$4.75 / month",
                anchorPrice: "$71.88",
                savings: "20% OFF",
                trialDays: 7,
                isRecommended: true
            ),
            SubscriptionPlan(
                id: "dawn.monthly",
                title: "Monthly",
                price: "$5.99",
                period: "per month",
                periodMonths: 1,
                equivalentMonthly: nil,
                anchorPrice: nil,
                savings: nil,
                trialDays: nil,
                isRecommended: false
            )
        ]
    }

    func refreshStatus() async -> SubscriptionStatus {
        guard defaults.bool(forKey: key) else { return .notSubscribed }
        return .subscribed(
            expires: Calendar.current.date(byAdding: .year, value: 1, to: .now),
            willRenew: true,
            productID: defaults.string(forKey: productKey)
        )
    }

    func purchase(_ plan: SubscriptionPlan) async throws -> SubscriptionStatus {
        try? await Task.sleep(for: .milliseconds(900))
        defaults.set(true, forKey: key)
        defaults.set(plan.id, forKey: productKey)
        return await refreshStatus()
    }

    func restore() async throws -> SubscriptionStatus {
        try? await Task.sleep(for: .milliseconds(700))
        guard defaults.bool(forKey: key) else { throw PurchaseFailure.nothingToRestore }
        return await refreshStatus()
    }

    private var key: String { "dawn.local.subscribed.\(userID ?? "anon")" }
    private var productKey: String { "dawn.local.product.\(userID ?? "anon")" }
}
