import Foundation
import Observation

/// Owns entitlement state for the whole app. The paywall reads `plans`, the
/// root gate reads `isSubscribed`, and the account screen reads `status`.
@Observable
@MainActor
final class SubscriptionController {
    private(set) var status: SubscriptionStatus = .unknown
    private(set) var plans: [SubscriptionPlan] = []
    private(set) var isLoadingPlans = false
    private(set) var isPurchasing = false
    private(set) var loadFailure: String?

    @ObservationIgnored private let provider: PurchaseProviding

    let usesLocalBackend: Bool

    init(provider: PurchaseProviding? = nil) {
        if let provider {
            self.provider = provider
            usesLocalBackend = false
        } else if let revenueCat = RevenueCatPurchaseProvider() {
            self.provider = revenueCat
            usesLocalBackend = false
        } else {
            self.provider = LocalPurchaseProvider()
            usesLocalBackend = true
        }
    }

    /// The gate. `.unknown` deliberately reads as *not* subscribed so a failed
    /// status check can never hand out the app for free — but the root view
    /// waits for a real answer before showing the paywall, so a slow network
    /// doesn't flash it at a paying customer.
    var isSubscribed: Bool { status.isActive }
    var hasResolvedStatus: Bool { status != .unknown }

    var recommendedPlan: SubscriptionPlan? {
        plans.first(where: \.isRecommended) ?? plans.first
    }

    // MARK: - Lifecycle

    func bind(to user: AuthUser?) async {
        if let user {
            await provider.identify(userID: user.id)
        } else {
            await provider.signOut()
        }
        await refreshStatus()
    }

    func refreshStatus() async {
        status = await provider.refreshStatus()
    }

    func loadPlans() async {
        guard !isLoadingPlans else { return }
        isLoadingPlans = true
        loadFailure = nil
        defer { isLoadingPlans = false }
        #if DEBUG
        if DebugHarness.wantsSlowStore { try? await Task.sleep(for: .seconds(8)) }
        #endif
        do {
            // Longest term first, so the annual card sits on the left whatever
            // order the store or the RevenueCat dashboard happens to return.
            plans = try await provider.loadPlans()
                .sorted { ($0.periodMonths ?? 0) > ($1.periodMonths ?? 0) }
        } catch {
            loadFailure = (error as? PurchaseFailure)?.errorDescription
                ?? error.localizedDescription
        }
    }

    // MARK: - Buying

    /// Returns true when the purchase left the user entitled.
    @discardableResult
    func purchase(_ plan: SubscriptionPlan) async throws -> Bool {
        guard !isPurchasing else { return false }
        isPurchasing = true
        defer { isPurchasing = false }
        status = try await provider.purchase(plan)
        return status.isActive
    }

    @discardableResult
    func restore() async throws -> Bool {
        guard !isPurchasing else { return false }
        isPurchasing = true
        defer { isPurchasing = false }
        status = try await provider.restore()
        return status.isActive
    }
}
