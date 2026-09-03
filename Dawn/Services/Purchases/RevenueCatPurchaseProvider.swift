import Foundation
import RevenueCat

/// Production billing, backed by RevenueCat.
///
/// Plan copy (savings %, monthly equivalent) is derived from the store's own
/// localised prices rather than hard-coded, so it stays correct in every
/// storefront and currency.
final class RevenueCatPurchaseProvider: PurchaseProviding {
    private let entitlementID: String
    private let offeringID: String?

    init?(apiKey: String = AppConfig.revenueCatAPIKey,
          entitlementID: String = AppConfig.entitlementID,
          offeringID: String = AppConfig.offeringID) {
        guard apiKey.hasPrefix("appl_") else { return nil }
        self.entitlementID = entitlementID
        self.offeringID = offeringID.isEmpty ? nil : offeringID

        Purchases.logLevel = .warn
        Purchases.configure(withAPIKey: apiKey)
    }

    // MARK: - Identity

    func identify(userID: String) async {
        _ = try? await Purchases.shared.logIn(userID)
    }

    func signOut() async {
        _ = try? await Purchases.shared.logOut()
    }

    // MARK: - Plans

    func loadPlans() async throws -> [SubscriptionPlan] {
        do {
            let offerings = try await Purchases.shared.offerings()
            let offering = offeringID.flatMap { offerings.offering(identifier: $0) } ?? offerings.current
            guard let packages = offering?.availablePackages, !packages.isEmpty else {
                throw PurchaseFailure.notAvailable
            }

            // Baseline for the savings badge: the cheapest month you could buy
            // without committing to a year.
            let monthlyBaseline = packages
                .compactMap { monthlyPrice(for: $0.storeProduct) }
                .max()

            return packages.map { plan(from: $0, monthlyBaseline: monthlyBaseline) }
        } catch {
            throw Self.mapped(error)
        }
    }

    private func plan(from package: Package, monthlyBaseline: Decimal?) -> SubscriptionPlan {
        let product = package.storeProduct
        let period = product.subscriptionPeriod
        let perMonth = monthlyPrice(for: product)

        var savings: String?
        var anchor: String?
        if let perMonth, let monthlyBaseline, monthlyBaseline > 0, perMonth < monthlyBaseline {
            let ratio = (monthlyBaseline - perMonth) / monthlyBaseline
            let percent = Int((ratio as NSDecimalNumber).doubleValue * 100)
            if percent >= 5 { savings = "\(percent)% OFF" }

            // What this same span would cost at the monthly rate.
            if let months = periodInMonths(period) {
                anchor = format(monthlyBaseline * months, like: product)
            }
        }

        var equivalent: String?
        if let perMonth, period?.unit == .year {
            equivalent = "\(format(perMonth, like: product)) / month"
        }

        return SubscriptionPlan(
            id: package.identifier,
            title: title(for: period, fallback: product.localizedTitle),
            price: product.localizedPriceString,
            period: periodLabel(for: period),
            periodMonths: periodInMonths(period).map { NSDecimalNumber(decimal: $0).doubleValue },
            equivalentMonthly: equivalent,
            anchorPrice: anchor,
            savings: savings,
            trialDays: trialDays(for: product),
            isRecommended: period?.unit == .year
        )
    }

    // MARK: - Status

    func refreshStatus() async -> SubscriptionStatus {
        guard let info = try? await Purchases.shared.customerInfo() else { return .unknown }
        return Self.status(from: info, entitlementID: entitlementID)
    }

    func purchase(_ plan: SubscriptionPlan) async throws -> SubscriptionStatus {
        do {
            let offerings = try await Purchases.shared.offerings()
            let offering = offeringID.flatMap { offerings.offering(identifier: $0) } ?? offerings.current
            guard let package = offering?.availablePackages.first(where: { $0.identifier == plan.id })
            else { throw PurchaseFailure.notAvailable }

            let result = try await Purchases.shared.purchase(package: package)
            if result.userCancelled { throw PurchaseFailure.cancelled }
            return Self.status(from: result.customerInfo, entitlementID: entitlementID)
        } catch {
            throw Self.mapped(error)
        }
    }

    func restore() async throws -> SubscriptionStatus {
        do {
            let info = try await Purchases.shared.restorePurchases()
            let status = Self.status(from: info, entitlementID: entitlementID)
            guard status.isActive else { throw PurchaseFailure.nothingToRestore }
            return status
        } catch {
            throw Self.mapped(error)
        }
    }

    // MARK: - Derivations

    private func monthlyPrice(for product: StoreProduct) -> Decimal? {
        guard let period = product.subscriptionPeriod,
              let months = periodInMonths(period), months > 0 else { return nil }
        return product.price / months
    }

    private func periodInMonths(_ period: SubscriptionPeriod?) -> Decimal? {
        guard let period else { return nil }
        switch period.unit {
        case .day: return Decimal(period.value) / 30
        case .week: return Decimal(period.value) / 4
        case .month: return Decimal(period.value)
        case .year: return Decimal(period.value) * 12
        @unknown default: return nil
        }
    }

    /// Formats a derived amount so it can't visually disagree with the price
    /// the store printed next to it.
    ///
    /// Apple's `displayPrice` is authoritative and is *not* reproducible with a
    /// local formatter. On a device in `en_NP` against a US storefront, Apple
    /// renders "USD 6.99" while every locally-built formatter — including
    /// StoreKit 2's own `priceFormatStyle` — produces "US$6.99". A struck-out
    /// "US$83.88" sitting beside a real "USD 69.99" reads as a bug.
    ///
    /// So rather than reformat, keep Apple's string and substitute the number
    /// inside it. The currency symbol, its position and the spacing all come
    /// from Apple; only the digits are ours.
    private func format(_ amount: Decimal, like product: StoreProduct) -> String {
        let template = product.localizedPriceString

        guard let digits = Self.numericRange(in: template),
              let rendered = Self.decimalString(amount, like: product)
        else { return Self.fallback(amount, like: product) }

        return template.replacingCharacters(in: digits, with: rendered)
    }

    /// The number inside a formatted price, separators included.
    private static func numericRange(in text: String) -> Range<String.Index>? {
        guard let first = text.firstIndex(where: \.isNumber) else { return nil }
        var last = first
        var index = first
        while index < text.endIndex {
            let character = text[index]
            if character.isNumber {
                last = index
            } else if !Self.groupingCharacters.contains(character) {
                break
            }
            index = text.index(after: index)
        }
        return first..<text.index(after: last)
    }

    /// Separators that can appear *inside* a number across locales — decimal
    /// points, thousands marks, and the various non-breaking spaces.
    private static let groupingCharacters: Set<Character> = [
        ".", ",", "'", " ", "\u{00A0}", "\u{202F}", "\u{2009}"
    ]

    private static func decimalString(_ amount: Decimal, like product: StoreProduct) -> String? {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = product.priceFormatter?.locale ?? .current
        // Match the store's own precision so 83.9 never appears beside 69.99.
        formatter.minimumFractionDigits = product.priceFormatter?.minimumFractionDigits ?? 2
        formatter.maximumFractionDigits = product.priceFormatter?.maximumFractionDigits ?? 2
        return formatter.string(from: amount as NSDecimalNumber)
    }

    private static func fallback(_ amount: Decimal, like product: StoreProduct) -> String {
        if let formatter = product.priceFormatter,
           let formatted = formatter.string(from: amount as NSDecimalNumber) {
            return formatted
        }
        return product.localizedPriceString
    }

    private func title(for period: SubscriptionPeriod?, fallback: String) -> String {
        guard let period else { return fallback }
        switch (period.unit, period.value) {
        case (.year, 1): return "Annual"
        case (.month, 1): return "Monthly"
        case (.month, let n): return "\(n) months"
        case (.week, 1): return "Weekly"
        default: return fallback
        }
    }

    private func periodLabel(for period: SubscriptionPeriod?) -> String {
        guard let period else { return "one time" }
        switch (period.unit, period.value) {
        case (.year, 1): return "per year"
        case (.month, 1): return "per month"
        case (.week, 1): return "per week"
        case (.day, let n): return "every \(n) days"
        case (.month, let n): return "every \(n) months"
        default: return ""
        }
    }

    private func trialDays(for product: StoreProduct) -> Int? {
        guard let intro = product.introductoryDiscount,
              intro.paymentMode == .freeTrial else { return nil }
        let period = intro.subscriptionPeriod
        switch period.unit {
        case .day: return period.value
        case .week: return period.value * 7
        case .month: return period.value * 30
        case .year: return period.value * 365
        @unknown default: return nil
        }
    }

    private static func status(from info: CustomerInfo, entitlementID: String) -> SubscriptionStatus {
        guard let entitlement = info.entitlements[entitlementID], entitlement.isActive else {
            return .notSubscribed
        }
        return .subscribed(
            expires: entitlement.expirationDate,
            willRenew: entitlement.willRenew,
            productID: entitlement.productIdentifier
        )
    }

    private static func mapped(_ error: Error) -> PurchaseFailure {
        if let failure = error as? PurchaseFailure { return failure }

        if let rcError = error as? RevenueCat.ErrorCode {
            switch rcError {
            case .purchaseCancelledError: return .cancelled
            case .paymentPendingError: return .pending
            case .networkError, .offlineConnectionError: return .network
            case .productNotAvailableForPurchaseError, .configurationError: return .notAvailable
            default: return .store(rcError.localizedDescription)
            }
        }

        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain { return .network }
        // RevenueCat surfaces its codes through NSError too.
        if nsError.domain == RevenueCat.ErrorCode.errorDomain,
           let code = RevenueCat.ErrorCode(rawValue: nsError.code) {
            switch code {
            case .purchaseCancelledError: return .cancelled
            case .paymentPendingError: return .pending
            case .networkError, .offlineConnectionError: return .network
            default: break
            }
        }
        return .store(error.localizedDescription)
    }
}
