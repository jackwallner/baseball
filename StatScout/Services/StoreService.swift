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
    #if DEBUG
    static let apiKey = "test_LwVQkuPHKAMldYwZpzbPktrjOlA"
    #else
    static let apiKey = "appl_qNlZGCCfGWBTsvcxlqYSNCtRupx"
    #endif
    /// The entitlement identifier RevenueCat actually returns in
    /// `customerInfo.entitlements.active`, verified against the dashboard.
    /// It is the entitlement's lookup key, not its display name ("StatScout+").
    ///
    /// This was wrong for a long time and nothing looked broken, because
    /// `hasProEntitlement` falls back to product ownership and the three App
    /// Store product ids do match. Anything that grants the entitlement
    /// *without* one of those exact product ids (an offer code, a manual grant
    /// from the dashboard, a renamed or newly added product) unlocked nothing.
    static let proEntitlement = "Baseball Savvy StatScout Pro"
    /// Historic/alternate identifiers, kept so a dashboard rename cannot lock
    /// existing subscribers out mid-flight.
    static let legacyEntitlements = ["StatScout Pro", "pro"]
}

enum StatScoutSeason {
    /// The season the nightly pipeline is currently writing. Single source of
    /// truth for the current/historical split, the API filters, the two-tier
    /// cache partition, and the free-tier gate all read this, so the yearly
    /// rollover is a one-line change.
    static let current = 2026
    /// The only season available without Pro. Everything older is gated.
    static let free = current
    /// Oldest season in the dataset. Statcast percentile history runs from
    /// 2015, and the bundled players-historical.plist ships all of it, so the
    /// season menus can list every year without waiting on a fetch.
    static let earliest = 2015
}

enum StatScoutLegal {
    /// Apple's standard EULA, required on the paywall unless a custom one is hosted.
    static let termsURL = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!
    static let privacyURL = URL(string: "https://jackwallner.github.io/baseball/privacy-policy.html")!
}

/// Session-scoped cap so the same contextual paywall can't be re-presented
/// endlessly as a user pokes at locked features. Resets on app relaunch.
@MainActor
final class PaywallGate: ObservableObject {
    static let shared = PaywallGate()
    private var presentedCount: [PaywallTrigger: Int] = [:]
    private let maxPerTrigger = 2

    /// Returns true if the paywall for this trigger may still be shown.
    /// User-explicit entry points (Settings, toolbar) should bypass this.
    func shouldPresent(_ trigger: PaywallTrigger) -> Bool {
        presentedCount[trigger, default: 0] < maxPerTrigger
    }

    func markPresented(_ trigger: PaywallTrigger) {
        presentedCount[trigger, default: 0] += 1
    }
}

enum PurchaseState {
    case purchased
    case cancelled
    case pending
}

/// Result of a one-tap CTA that transacts the yearly plan in place.
///
/// `.needsPlanPicker` is the only case that may open `PaywallView`: it means
/// the offering never loaded, so there is nothing to buy and the plan picker's
/// retry/empty state is the honest answer. Every other case is handled inline.
enum DirectPurchaseOutcome: Equatable {
    case unlocked
    case pending
    case cancelled
    case failed(String)
    case needsPlanPicker
}

enum StoreServiceError: LocalizedError {
    case purchasesUnavailableInSimulator

    var errorDescription: String? {
        switch self {
        case .purchasesUnavailableInSimulator:
            return "Purchases are unavailable in simulator builds."
        }
    }
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

    /// Localized per-month price for any recurring package. For a yearly
    /// product priced at $29.99/yr this returns "$2.50". Lifetime / non-
    /// recurring products return nil. Used on the paywall plan card so the
    /// annual price doesn't look like sticker shock next to monthly.
    var monthlyEquivalentLabel: String? {
        guard let period = storeProduct.subscriptionPeriod else { return nil }
        let monthsDecimal: Decimal
        switch period.unit {
        case .day:   monthsDecimal = Decimal(period.value) / Decimal(30)
        case .week:  monthsDecimal = Decimal(period.value) * Decimal(7) / Decimal(30)
        case .month: monthsDecimal = Decimal(period.value)
        case .year:  monthsDecimal = Decimal(period.value) * Decimal(12)
        @unknown default: return nil
        }
        // Only show /mo breakdown for periods that aren't already monthly,
        // showing "$4.99/mo" under a "$4.99/month" price is noise.
        guard monthsDecimal > 1 else { return nil }
        let perMonth = storeProduct.price / monthsDecimal
        let formatter = storeProduct.priceFormatter ?? Self.defaultCurrencyFormatter(currencyCode: storeProduct.currencyCode)
        return formatter.string(from: perMonth as NSDecimalNumber)
    }

    /// Compact "/mo" label suitable for a strike-through anchor on the yearly
    /// card. Returns the package's localized monthly price (per-month for an
    /// annual product, the price itself for a true monthly product).
    var monthlyEquivalentAnchorLabel: String? {
        switch productKind {
        case .monthly:
            return "\(storeProduct.localizedPriceString)/mo"
        case .yearly, .lifetime, .other:
            guard let perMonth = monthlyEquivalentLabel else { return nil }
            return "\(perMonth)/mo"
        }
    }

    private static func defaultCurrencyFormatter(currencyCode: String?) -> NumberFormatter {
        let f = NumberFormatter()
        f.numberStyle = .currency
        if let code = currencyCode { f.currencyCode = code }
        return f
    }

    var introOfferLabel: String? {
        #if DEBUG && targetEnvironment(simulator)
        if RevenueCatConfig.apiKey.hasPrefix("test_"), productKind == .monthly || productKind == .yearly {
            return "7-day free trial"
        }
        #endif
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
            || RevenueCatConfig.legacyEntitlements.contains(where: { active[$0]?.isActive == true }) {
            return true
        }
        // This project has exactly one entitlement, so any active one is Pro.
        // Named lookups above stay first for intent; this catches a dashboard
        // rename without shipping a build.
        if active.values.contains(where: { $0.isActive }) {
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
    /// Paywall display order: yearly first (conversion default with trial +
    /// savings badge), then monthly (price anchor), then lifetime (commitment).
    var sortedPackages: [Package] {
        let displayOrder: [RCProductKind] = [.yearly, .monthly, .lifetime, .other]
        return availablePackages.sorted {
            let lhs = displayOrder.firstIndex(of: $0.productKind) ?? displayOrder.count
            let rhs = displayOrder.firstIndex(of: $1.productKind) ?? displayOrder.count
            if lhs != rhs { return lhs < rhs }
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
    #if DEBUG
    /// Local-only StatScout+ override so Pro-gated surfaces (Recent Form,
    /// past seasons, Compare) can be exercised in the simulator, where
    /// RevenueCat is intentionally never configured. Set the
    /// `STATSCOUT_FORCE_PRO=1` environment variable on the scheme/launch.
    @Published private(set) var isPro: Bool = ProcessInfo.processInfo.environment["STATSCOUT_FORCE_PRO"] == "1"
    #else
    @Published private(set) var isPro: Bool = false
    #endif
    @Published private(set) var purchaseInFlight: Bool = false
    @Published private(set) var isLoadingProducts: Bool = false
    @Published private(set) var lastError: String?

    /// Per-product intro-offer eligibility. Populated with `fetchProducts` so
    /// trial copy only appears for users StoreKit will actually grant a trial.
    @Published private(set) var introEligibility: [String: Bool] = [:]

    private var paywallImpressionsThisSession: Set<String> = []

    var proPrice: String? {
        products.first(where: { $0.productKind == .lifetime })?.storeProduct.localizedPriceString
    }

    /// CTA label for the blurred contextual paywalls (Year Compare, Player
    /// Compare). Leads with the yearly free-trial offer when available so the
    /// upsell emphasizes the low-friction option instead of the lifetime price.
    var paywallBlurCTA: String {
        directCTALabel(for: .upgrade)
    }

    /// The short label every "go to StatScout+" entry point wears: the toolbar
    /// pill, the Settings button, the leaderboard footer. Trial-aware, because
    /// "Try Free" converts and "Upgrade" reads as an account setting, but the
    /// same everywhere, because three names for one door is three doors.
    ///
    /// This is the terse form. The direct-purchase CTAs that actually take the
    /// money use `directCTALabel(for:)`, which carries the price.
    ///
    /// Split into a pure function over one Bool so the copy is unit-testable.
    /// It otherwise wasn't testable anywhere: `configureIfNeeded()` refuses to
    /// configure RevenueCat on a simulator, so `yearlyPackage` is nil in every
    /// simulator run and a `.storekit` config can't change that. The trial
    /// branch could only ever be seen on a real device.
    nonisolated static func upgradeCTALabel(trialAvailable: Bool) -> String {
        trialAvailable ? "Try Free" : "Upgrade"
    }

    /// Whether the yearly plan is currently offering an intro trial this user
    /// is eligible to take.
    var isYearlyTrialAvailable: Bool {
        #if DEBUG
        // Simulator-only: lets the trial-copy state of every upgrade surface be
        // captured headlessly, since the real path needs a device. Same shape
        // as the existing STATSCOUT_FORCE_PRO hook, and stripped from Release.
        if ProcessInfo.processInfo.environment["STATSCOUT_FORCE_TRIAL_CTA"] == "1" { return true }
        #endif
        guard let yearly = yearlyPackage else { return false }
        return isEligibleForIntroOffer(yearly) && yearly.introOfferLabel != nil
    }

    var upgradeCTALabel: String {
        Self.upgradeCTALabel(trialAvailable: isYearlyTrialAvailable)
    }

    func directCTALabel(for trigger: PaywallTrigger) -> String {
        if let yearly = yearlyPackage {
            if trigger != .winback,
               isEligibleForIntroOffer(yearly),
               let trial = yearly.introOfferLabel {
                return "Start \(trial)"
            }
            let verb = trigger == .winback ? "Restart" : "Try"
            return "\(verb) StatScout+ for \(yearly.priceLabel)"
        }
        if let price = proPrice {
            let verb = trigger == .winback ? "Restart" : "Unlock"
            return "\(verb) StatScout+ for \(price)"
        }
        return trigger == .winback ? "Restart StatScout+" : "Unlock StatScout+"
    }

    /// One-line secondary caption shown under the CTA when a trial is offered,
    /// so the price after the trial isn't hidden.
    var paywallBlurSubtext: String? {
        guard let yearly = products.first(where: { $0.productKind == .yearly }),
              isEligibleForIntroOffer(yearly),
              yearly.introOfferLabel != nil else { return nil }
        return "Then \(yearly.priceLabel). Cancel anytime."
    }

    /// The yearly package, the one-tap conversion target for every trial /
    /// teaser pop-up (onboarding, TrialPitchSheet, blur CTAs). Those surfaces
    /// purchase this directly, trial or not; the full `PaywallView` is only the
    /// fallback when this is nil (products not loaded), or for deliberate
    /// upgrade entry points where the user should pick a plan.
    var yearlyPackage: Package? {
        products.first { $0.productKind == .yearly }
    }

    /// Full Apple-3.1.2 auto-renew disclosure for the yearly plan, shown next
    /// to any direct-purchase CTA so the price (and trial terms, when offered)
    /// are present at the point of purchase.
    var yearlyCTADisclosureText: String? {
        guard let yearly = yearlyPackage else { return nil }
        let renew = "Auto-renews unless cancelled at least 24 hours before the end of the current period. Manage or cancel in Settings › Apple ID › Subscriptions."
        if isEligibleForIntroOffer(yearly), let trial = yearly.introOfferLabel {
            return "\(trial.capitalized), then \(yearly.priceLabel). \(renew)"
        }
        return "\(yearly.priceLabel). \(renew)"
    }

    var onboardingMonthlyCTALabel: String {
        guard let monthly = monthlyPackage else { return "Upgrade to StatScout+" }
        if isEligibleForIntroOffer(monthly), let trial = monthly.introOfferLabel {
            return "Start \(trial)"
        }
        return "Try StatScout+ for \(monthly.priceLabel)"
    }

    var onboardingMonthlyDisclosureText: String? {
        guard let monthly = monthlyPackage else { return nil }
        let renew = "Auto-renews unless cancelled at least 24 hours before the end of the current period. Manage or cancel in Settings › Apple ID › Subscriptions."
        if isEligibleForIntroOffer(monthly), let trial = monthly.introOfferLabel {
            return "\(trial.capitalized), then \(monthly.priceLabel). \(renew)"
        }
        return "\(monthly.priceLabel). \(renew)"
    }

    /// The monthly package, when present. Used as the anchor when computing
    /// yearly savings % and rendering a strike-through monthly-equivalent price.
    var monthlyPackage: Package? {
        products.first { $0.productKind == .monthly }
    }

    /// Integer savings % the yearly package offers vs. 12× the monthly price.
    /// Returns nil unless both packages are present and the math is favorable.
    func yearlySavingsPercent(yearly: Package) -> Int? {
        guard yearly.productKind == .yearly, let monthly = monthlyPackage else { return nil }
        let yearlyPrice = yearly.storeProduct.price
        let twelveMonths = monthly.storeProduct.price * Decimal(12)
        guard twelveMonths > 0, yearlyPrice < twelveMonths else { return nil }
        let saving = (twelveMonths - yearlyPrice) / twelveMonths * Decimal(100)
        var rounded = Decimal()
        var src = saving
        NSDecimalRound(&rounded, &src, 0, .plain)
        let percent = NSDecimalNumber(decimal: rounded).intValue
        return percent > 0 ? percent : nil
    }

    /// Strike-through anchor price for the yearly card, "$4.99/mo" if a
    /// monthly package exists. Nil when there's nothing to anchor against.
    var monthlyAnchorPriceLabel: String? {
        monthlyPackage?.monthlyEquivalentAnchorLabel
    }

    /// True when this package advertises a free trial and the user is eligible.
    /// Unknown eligibility resolves to true so a transient lookup failure does
    /// not hide a trial the user likely qualifies for (Vitals pattern).
    func isEligibleForIntroOffer(_ package: Package) -> Bool {
        guard package.introOfferLabel != nil else { return false }
        return introEligibility[package.storeProduct.productIdentifier] ?? true
    }

    /// Reports a custom-paywall impression to RevenueCat (required for native UI).
    func trackPaywallImpression(id: String, oncePerSession: Bool = false) {
        guard configureIfNeeded() else { return }
        #if DEBUG
        if ProcessInfo.processInfo.environment["FORCE_PRO"] == "1" { return }
        #endif
        if oncePerSession {
            guard !paywallImpressionsThisSession.contains(id) else { return }
            paywallImpressionsThisSession.insert(id)
        }
        ConversionDiagnostics.recordPitchView(impressionID: id)
        syncConversionAttributes()
        Purchases.shared.trackCustomPaywallImpression(
            CustomPaywallImpressionParams(paywallId: id)
        )
    }

    /// Mirrors the on-device paywall record onto the RevenueCat customer.
    ///
    /// Attributes rather than extra impressions: RevenueCat treats every
    /// impression id as a paywall encounter, so funnel steps sent that way would
    /// drive the encounter rate to 100% and destroy the one server-side number
    /// that currently works.
    ///
    /// `configureIfNeeded()` is the load-bearing guard. `Purchases.shared` traps
    /// when RevenueCat was never configured, which is every simulator run.
    func syncConversionAttributes() {
        guard configureIfNeeded() else { return }
        var attributes = ConversionDiagnostics.subscriberAttributes
        guard !attributes.isEmpty else { return }
        if let offering = currentOffering?.identifier {
            attributes["offering_id"] = offering
        }
        Purchases.shared.attribution.setAttributes(attributes)
    }

    /// True when the user once held a Pro entitlement that has since expired and
    /// isn't currently active. Used to show a tailored win-back paywall.
    var isLapsed: Bool {
        guard !isPro, let info = customerInfo else { return false }
        return info.entitlements.all.values.contains { entitlement in
            !entitlement.isActive
                && (entitlement.expirationDate.map { $0 < Date() } ?? false)
        }
    }

    /// The generic "upgrade" ask, swapped to a win-back variant for lapsed users.
    var defaultUpgradeTrigger: PaywallTrigger {
        isLapsed ? .winback : .upgrade
    }

    private let logger = Logger(subsystem: "com.jackwallner.baseball", category: "Store")
    private var isConfigured = false

    private override init() {}

    func start() {
        #if DEBUG
        // UI-test / local hook: force Pro so the gated surfaces (Recent Form,
        // Compare) render without a sandbox purchase. Never compiled into Release.
        if ProcessInfo.processInfo.environment["FORCE_PRO"] == "1" {
            isPro = true
            return
        }
        #endif
        guard configureIfNeeded() else { return }
        Task { await updateCustomerProductStatus(fetchPolicy: .fetchCurrent) }
        Task { await fetchProducts() }
    }

    /// Loads the offering, retrying a couple of times before giving up.
    ///
    /// App Review runs behind a VPN on a cold device, which is exactly the
    /// shape of network where a single `offerings()` call times out. One
    /// failure used to leave `products` empty for the rest of the session, and
    /// every CTA in the app then had nothing to sell: the tap fell through to
    /// the plan picker's error state, which reads as "the purchase errored".
    func fetchProducts() async {
        guard configureIfNeeded() else { return }
        isLoadingProducts = true
        defer { isLoadingProducts = false }
        var attempt = 0
        while attempt < 3 {
            do {
                let offerings = try await Purchases.shared.offerings()
                let offering = offerings.paywallOffering
                currentOffering = offering
                products = offering?.sortedPackages ?? []
                lastError = nil
                await refreshIntroEligibility()
                return
            } catch {
                attempt += 1
                logger.error("Product fetch failed (attempt \(attempt, privacy: .public)): \(String(describing: error), privacy: .public)")
                if attempt < 3 {
                    try? await Task.sleep(nanoseconds: UInt64(attempt) * 700_000_000)
                }
            }
        }
        lastError = "Couldn't load subscription options. Check your connection and try again."
    }

    /// Guarantees the offering is loaded before a CTA transacts, so a tap on a
    /// priced button buys that plan instead of bouncing to the plan picker.
    /// Returns true when something is actually purchasable afterwards.
    @discardableResult
    func ensureProductsLoaded() async -> Bool {
        if !products.isEmpty { return true }
        await fetchProducts()
        return !products.isEmpty
    }

    @discardableResult
    func purchase(_ product: Package) async throws -> PurchaseState {
        guard configureIfNeeded() else {
            throw StoreServiceError.purchasesUnavailableInSimulator
        }
        // A purchase must never inherit a message from an earlier, unrelated
        // failure. `lastError` is the shared status line every surface reads,
        // so a stale "Couldn't load subscription options" from a cold launch
        // would otherwise surface as the *purchase's* error the moment a
        // transaction takes any other path than success.
        lastError = nil
        purchaseInFlight = true
        defer { purchaseInFlight = false }

        let startedTrial = isEligibleForIntroOffer(product)
        do {
            let result = try await Purchases.shared.purchase(package: product)
            apply(customerInfo: result.customerInfo)
            if result.userCancelled {
                return .cancelled
            }
            if result.customerInfo.hasProEntitlement {
                ConversionDiagnostics.recordConversion(
                    plan: product.storeProduct.productIdentifier,
                    startedTrial: startedTrial,
                    offeringID: currentOffering?.identifier
                )
                syncConversionAttributes()
                return .purchased
            }
            // The purchase went through but the entitlement is not in the
            // customer info we were handed. That is what a genuinely deferred
            // (Ask to Buy) purchase looks like, and it is also what a race
            // against RevenueCat's backend looks like. Ask once, authoritatively,
            // before telling a buyer their purchase is pending: calling a
            // completed purchase "pending" leaves them paid and locked out.
            await updateCustomerProductStatus(fetchPolicy: .fetchCurrent)
            return isPro ? .purchased : .pending
        } catch {
            // RevenueCat reports a cancelled sheet as a thrown error in some
            // StoreKit paths, not just via `userCancelled`. Cancelling is a
            // normal outcome, never an error to show the user.
            if let rcError = error as? RevenueCat.ErrorCode, rcError == .purchaseCancelledError {
                return .cancelled
            }
            let nsError = error as NSError
            if nsError.domain == RevenueCat.ErrorCode.errorDomain,
               let code = RevenueCat.ErrorCode(rawValue: nsError.code) {
                switch code {
                case .purchaseCancelledError:
                    return .cancelled
                case .paymentPendingError:
                    return .pending
                case .productAlreadyPurchasedError, .receiptAlreadyInUseError:
                    // Already entitled on this Apple ID: settle it as a restore
                    // rather than telling the buyer their purchase failed.
                    await updateCustomerProductStatus(fetchPolicy: .fetchCurrent)
                    return isPro ? .purchased : .pending
                default:
                    break
                }
            }
            logger.error("Purchase failed: \(String(describing: error), privacy: .public)")
            lastError = Self.purchaseFailureMessage(for: error)
            throw error
        }
    }

    /// Human-readable, purchase-specific failure copy. Never generic enough to
    /// read as "the app is broken", and never borrowed from another operation.
    nonisolated static func purchaseFailureMessage(for error: Error) -> String {
        let nsError = error as NSError
        if nsError.domain == RevenueCat.ErrorCode.errorDomain,
           let code = RevenueCat.ErrorCode(rawValue: nsError.code) {
            switch code {
            case .networkError, .offlineConnectionError:
                return "Couldn't reach the App Store. Check your connection and try again."
            case .storeProblemError:
                return "The App Store is temporarily unavailable. Please try again in a moment."
            case .purchaseNotAllowedError:
                return "Purchases are turned off for this device. Check Screen Time › Content & Privacy Restrictions."
            case .purchaseInvalidError:
                return "This Apple ID can't complete the purchase. Try again, or use a different Apple ID."
            case .productNotAvailableForPurchaseError:
                return "StatScout+ isn't available for purchase on this account's App Store region right now."
            case .ineligibleError:
                return "That offer isn't available on this Apple ID. Tap again to subscribe at the regular price."
            default:
                break
            }
        }
        return "Couldn't complete the purchase. Please try again."
    }

    /// The single conversion path behind every pitch in the app.
    ///
    /// A CTA that names an offer ("Start 7-day free trial") has to *be* that
    /// offer: the next thing the user sees is Apple's confirm sheet, never a
    /// second pitch asking them to agree again. Surfaces that used to hand off
    /// to `PaywallView` call this instead; the plan picker is now reachable
    /// only from a deliberate "See all plans" link, or as the fallback when the
    /// offering failed to load and there is genuinely nothing to buy.
    func purchaseYearlyDirect() async -> DirectPurchaseOutcome {
        if yearlyPackage == nil {
            await ensureProductsLoaded()
        }
        guard let yearly = yearlyPackage else { return .needsPlanPicker }
        do {
            switch try await purchase(yearly) {
            case .purchased:
                return .unlocked
            case .pending:
                return .pending
            case .cancelled:
                return .cancelled
            }
        } catch {
            return .failed(Self.purchaseFailureMessage(for: error))
        }
    }

    func updateCustomerProductStatus(fetchPolicy: CacheFetchPolicy = .default) async {
        guard configureIfNeeded() else { return }
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
        guard configureIfNeeded() else {
            lastError = StoreServiceError.purchasesUnavailableInSimulator.localizedDescription
            return
        }
        lastError = nil
        do {
            let info = try await Purchases.shared.restorePurchases()
            apply(customerInfo: info)
            lastError = isPro ? nil : "No active StatScout+ purchase was found for this Apple ID."
        } catch {
            logger.error("Restore failed: \(String(describing: error), privacy: .public)")
            lastError = "Couldn't restore purchases. Try again."
        }
    }

    private func refreshIntroEligibility() async {
        let identifiers = products
            .filter { $0.storeProduct.introductoryDiscount != nil }
            .map(\.storeProduct.productIdentifier)
        guard !identifiers.isEmpty else {
            introEligibility = [:]
            return
        }
        let result = await Purchases.shared.checkTrialOrIntroDiscountEligibility(productIdentifiers: identifiers)
        introEligibility = result.mapValues { $0.status == .eligible }
    }

    func apply(customerInfo: CustomerInfo) {
        self.customerInfo = customerInfo
        let activeKeys = customerInfo.entitlements.active.keys.sorted().joined(separator: ", ")
        let allKeys = customerInfo.entitlements.all.keys.sorted().joined(separator: ", ")
        logger.info("Applied customerInfo, active: [\(activeKeys, privacy: .public)] all: [\(allKeys, privacy: .public)]")
        let hasActiveSubscription = customerInfo.hasProEntitlement
        if isPro != hasActiveSubscription {
            isPro = hasActiveSubscription
            logger.info("isPro updated to \(hasActiveSubscription, privacy: .public)")
        }
    }

    @discardableResult
    private func configureIfNeeded() -> Bool {
        guard !isConfigured else { return true }
        #if targetEnvironment(simulator)
        #if DEBUG
        // The one simulator path allowed to configure RevenueCat, and only ever
        // with the Test Store key: a separate RevenueCat app inside the same
        // project, so a probe run cannot touch App Store customers, revenue or
        // charts. See RevenueCatProbe.
        if RevenueCatProbe.isEnabled {
            Purchases.logLevel = .debug
            Purchases.configure(
                with: Configuration.Builder(withAPIKey: RevenueCatProbe.testStoreKey)
                    .with(appUserID: RevenueCatProbe.appUserID)
                    .build()
            )
            Purchases.shared.delegate = self
            isConfigured = true
            return true
        }
        #endif
        guard RevenueCatConfig.apiKey.hasPrefix("test_") else { return false }
        #endif
        #if DEBUG
        Purchases.logLevel = .debug
        #endif
        Purchases.configure(withAPIKey: RevenueCatConfig.apiKey)
        Purchases.shared.delegate = self
        isConfigured = true
        return true
    }
}

extension StoreService: PurchasesDelegate {
    nonisolated func purchases(_ purchases: Purchases, receivedUpdated customerInfo: CustomerInfo) {
        Task { @MainActor in
            StoreService.shared.apply(customerInfo: customerInfo)
        }
    }
}

#if DEBUG
/// Simulator-only proof path for the fleet-wide funnel attributes.
///
/// Under the normal rules the attributes cannot be verified on a simulator: the
/// production key must never be configured there, so RevenueCat is never
/// configured, so nothing is ever sent, so a physical device is the only
/// witness. The Test Store key is a different RevenueCat app inside the same
/// project, so a probe run cannot touch App Store customers, revenue or charts.
///
/// DEBUG only, and only with the launch argument, so it cannot reach a Release
/// build or an ordinary simulator run.
enum RevenueCatProbe {
    static var isEnabled: Bool {
        ProcessInfo.processInfo.arguments.contains("-rcfunnelprobe")
    }

    static let testStoreKey = "test_LwVQkuPHKAMldYwZpzbPktrjOlA"

    static var appUserID: String {
        ProcessInfo.processInfo.environment["RC_PROBE_USER"] ?? "funnel-probe-baseball"
    }

    static var impressionID: String {
        ProcessInfo.processInfo.environment["RC_PROBE_SURFACE"] ?? "statscout_paywall_upgrade"
    }

    /// Also run a purchase against the Test Store, so the `converted_*` half of
    /// the record is exercised and not just the impression half.
    ///
    /// Test Store purchases are simulated by RevenueCat: no StoreKit, no App
    /// Store, no revenue, and no real transaction. RevenueCat puts up its own
    /// confirmation sheet, so this needs a UI test to tap it, which is what
    /// `PaywallFunnelUITests` does.
    static var wantsPurchase: Bool {
        ProcessInfo.processInfo.arguments.contains("-rcfunnelprobepurchase")
    }
}
#endif
