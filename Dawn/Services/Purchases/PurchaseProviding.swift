import Foundation

protocol PurchaseProviding: AnyObject {
    /// Ties purchases to the signed-in account so a subscription follows the
    /// user across devices rather than sticking to one Apple Account.
    func identify(userID: String) async
    func signOut() async

    func loadPlans() async throws -> [SubscriptionPlan]
    func refreshStatus() async -> SubscriptionStatus
    func purchase(_ plan: SubscriptionPlan) async throws -> SubscriptionStatus
    func restore() async throws -> SubscriptionStatus
}
