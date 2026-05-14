import Foundation
import os
@preconcurrency import RevenueCat

enum StatScoutProduct {
    static let lifetime = "com.jackwallner.baseball.pro"
    static let yearly = "com.jackwallner.baseball.pro.yearly"
    static let monthly = "com.jackwallner.baseball.pro.monthly"
    static let all: [String] = [lifetime, yearly, monthly]
}

enum RevenueCatConfig {
    static let apiKey = "appl_qNlZGCCfGWBTsvcxlqYSNCtRupx"
    static let proEntitlement = "StatScout Pro"
    static let fallbackEntitlement = "pro"
}

enum PurchaseState {
    case purchased
    case cancelled
    case pending
}

enum RCProductKind: Int {
    case lifetime = 0
    case yearly = 1
    case monthly = 2
    case other = 3
}

extension RCProductKind {
    init(package: Package) {
        switch package.packageType {
        case .lifetime:
            self = .lifetime
        case .annual:
            self = .yearly
        case .monthly:
            self = .monthly
        default:
            let identifiers = [package.identifier, package.storeProduct.productIdentifier].map { $0.lowercased() }
            if identifiers.contains(where: { $0.contains(StatScoutProduct.lifetime.lowercased()) }) {
                self = .lifetime
            } else if identifiers.contains(where: { $0.contains(StatScoutProduct.yearly.lowercased()) || $0.contains("annual") }) {
                self = .yearly
            } else if identifiers.contains(where: { $0.contains(StatScoutProduct.monthly.lowercased()) }) {
                self = .monthly
            } else {
                self = .other
            }
        }
    }
}

extension Package {
    var productKind: RCProductKind {
        RCProductKind(package: self)
    }

    var displayName: String {
        switch productKind {
        case .lifetime: return "Lifetime"
        case .yearly: return "Yearly"
        case .monthly: return "Monthly"
        case .other: return storeProduct.localizedTitle
        }
    }

    var priceLabel: String {
        guard let period = storeProduct.subscriptionPeriod else { return storeProduct.localizedPriceString }
        let unit: String
        switch period.unit {
        case .day: unit = period.value == 1 ? "day" : "days"
        case .week: unit = period.value == 1 ? "week" : "weeks"
        case .month: unit = period.value == 1 ? "month" : "months"
        case .year: unit = period.value == 1 ? "year" : "years"
        @unknown default: unit = ""
        }
        if period.value == 1 {
            return "\(storeProduct.localizedPriceString) / \(unit)"
        } else {
            return "\(storeProduct.localizedPriceString) / \(period.value) \(unit)"
        }
    }

    var introOfferLabel: String? {
        guard let intro = storeProduct.introductoryDiscount, intro.paymentMode == .freeTrial else {
            return nil
        }
        let period = intro.subscriptionPeriod
        let unit: String
        switch period.unit {
        case .day: unit = period.value == 1 ? "day" : "days"
        case .week: unit = period.value == 1 ? "week" : "weeks"
        case .month: unit = period.value == 1 ? "month" : "months"
        case .year: unit = period.value == 1 ? "year" : "years"
        @unknown default: unit = ""
        }
        if period.unit == .week {
            return "\(period.value * 7)-day free trial"
        } else {
            return "\(period.value)-\(unit.dropLast(period.value == 1 ? 0 : 1)) free trial"
        }
    }
}

extension CustomerInfo {
    var hasProEntitlement: Bool {
        let active = entitlements.active
        if active[RevenueCatConfig.proEntitlement]?.isActive == true
            || active[RevenueCatConfig.fallbackEntitlement]?.isActive == true {
            return true
        }
        // Belt-and-suspenders: if the entitlement mapping on the dashboard is
        // missing or mis-named, fall back to product ownership. Lifetime is a
        // non-consumable; recurring products show up under activeSubscriptions.
        if nonSubscriptions.contains(where: { $0.productIdentifier == StatScoutProduct.lifetime }) {
            return true
        }
        let recurring: Set<String> = [StatScoutProduct.yearly, StatScoutProduct.monthly]
        if !activeSubscriptions.intersection(recurring).isEmpty {
            return true
        }
        return false
    }
}

extension Offering {
    var sortedPackages: [Package] {
        availablePackages.sorted {
            let lhsKind = $0.productKind
            let rhsKind = $1.productKind
            if lhsKind.rawValue != rhsKind.rawValue {
                return lhsKind.rawValue < rhsKind.rawValue
            }
            return $0.storeProduct.productIdentifier < $1.storeProduct.productIdentifier
        }
    }
}

extension Offerings {
    var paywallOffering: Offering? {
        offering(identifier: "default") ?? current
    }
}

@MainActor
final class StoreService: NSObject, ObservableObject {
    static let shared = StoreService()

    @Published private(set) var products: [Package] = []
    @Published private(set) var currentOffering: Offering?
    @Published private(set) var customerInfo: CustomerInfo?
    @Published private(set) var isPro: Bool = false
    @Published private(set) var purchaseInFlight: Bool = false
    @Published private(set) var isLoadingProducts: Bool = false
    @Published private(set) var lastError: String?

    var proPrice: String? {
        products.first(where: { $0.productKind == .lifetime })?.storeProduct.localizedPriceString
    }

    private let logger = Logger(subsystem: "com.jackwallner.baseball", category: "Store")
    private var isConfigured = false

    private override init() {}

    func start() {
        configureIfNeeded()
        Task { await updateCustomerProductStatus(fetchPolicy: .fetchCurrent) }
        Task { await fetchProducts() }
    }

    func fetchProducts() async {
        configureIfNeeded()
        isLoadingProducts = true
        defer { isLoadingProducts = false }
        do {
            let offerings = try await Purchases.shared.offerings()
            let offering = offerings.paywallOffering
            currentOffering = offering
            products = offering?.sortedPackages ?? []
            lastError = nil
        } catch {
            logger.error("Product fetch failed: \(String(describing: error), privacy: .public)")
            lastError = "Couldn't load subscription options. Check your connection and try again."
        }
    }

    @discardableResult
    func purchase(_ product: Package) async throws -> PurchaseState {
        configureIfNeeded()
        purchaseInFlight = true
        defer { purchaseInFlight = false }

        let result = try await Purchases.shared.purchase(package: product)
        apply(customerInfo: result.customerInfo)
        if result.userCancelled {
            return .cancelled
        } else if result.customerInfo.hasProEntitlement {
            return .purchased
        } else {
            return .pending
        }
    }

    func updateCustomerProductStatus(fetchPolicy: CacheFetchPolicy = .default) async {
        configureIfNeeded()
        do {
            let info = try await Purchases.shared.customerInfo(fetchPolicy: fetchPolicy)
            apply(customerInfo: info)
            lastError = nil
        } catch {
            logger.error("Customer info refresh failed: \(String(describing: error), privacy: .public)")
            lastError = "Couldn't refresh your subscription status. Check your connection and try again."
        }
    }

    func restorePurchases() async {
        configureIfNeeded()
        lastError = nil
        do {
            let info = try await Purchases.shared.restorePurchases()
            apply(customerInfo: info)
            lastError = isPro ? nil : "No active StatScout Pro purchase was found for this Apple ID."
        } catch {
            logger.error("Restore failed: \(String(describing: error), privacy: .public)")
            lastError = "Couldn't restore purchases. Try again."
        }
    }

    func apply(customerInfo: CustomerInfo) {
        self.customerInfo = customerInfo
        let activeKeys = customerInfo.entitlements.active.keys.sorted().joined(separator: ", ")
        let allKeys = customerInfo.entitlements.all.keys.sorted().joined(separator: ", ")
        logger.info("Applied customerInfo — active: [\(activeKeys, privacy: .public)] all: [\(allKeys, privacy: .public)]")
        let hasActiveSubscription = customerInfo.hasProEntitlement
        if isPro != hasActiveSubscription {
            isPro = hasActiveSubscription
            logger.info("isPro updated to \(hasActiveSubscription, privacy: .public)")
        }
    }

    private func configureIfNeeded() {
        guard !isConfigured else { return }
        #if DEBUG
        Purchases.logLevel = .debug
        #endif
        Purchases.configure(withAPIKey: RevenueCatConfig.apiKey)
        Purchases.shared.delegate = self
        isConfigured = true
    }
}

extension StoreService: PurchasesDelegate {
    nonisolated func purchases(_ purchases: Purchases, receivedUpdated customerInfo: CustomerInfo) {
        Task { @MainActor in
            StoreService.shared.apply(customerInfo: customerInfo)
        }
    }
}
