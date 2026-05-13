import Foundation
import StoreKit
import Observation

enum StoreError: LocalizedError {
    case failedVerification
    case pendingApproval
    case userCancelled
    case unknown

    var errorDescription: String? {
        switch self {
        case .failedVerification: "Purchase verification failed."
        case .pendingApproval: "Purchase is pending approval."
        case .userCancelled: "Purchase was cancelled."
        case .unknown: "An unknown error occurred."
        }
    }
}

enum ProStatus: Equatable {
    case notPurchased
    case purchased
    case loading
}

enum ProTier: String, CaseIterable {
    case monthly = "com.jackwallner.baseball.pro.monthly"
    case yearly = "com.jackwallner.baseball.pro.yearly"
    case lifetime = "com.jackwallner.baseball.pro"
}

@MainActor
@Observable
final class StoreManager {
    // Backwards-compatible alias used by callers that only know about the lifetime IAP.
    static let proUnlockID = ProTier.lifetime.rawValue

    private static let allProductIDs: Set<String> = Set(ProTier.allCases.map(\.rawValue))

    private(set) var products: [Product] = []
    private(set) var proStatus: ProStatus = .loading
    private(set) var purchaseError: String?

    private var transactionListener: Task<Void, Never>?

    func product(for tier: ProTier) -> Product? {
        products.first { $0.id == tier.rawValue }
    }

    var monthlyProduct: Product? { product(for: .monthly) }
    var yearlyProduct: Product? { product(for: .yearly) }
    var lifetimeProduct: Product? { product(for: .lifetime) }

    // Kept so existing callers continue to display the lifetime price.
    var proPrice: String? {
        lifetimeProduct?.displayPrice
    }

    init() {
        transactionListener = Task.detached { [weak self] in
            await self?.listenForTransactions()
        }
        Task { await loadProducts() }
        Task { await checkEntitlement() }
    }

    func loadProducts() async {
        do {
            products = try await Product.products(for: Self.allProductIDs)
            if products.isEmpty {
                purchaseError = "No products found. Verify product IDs in App Store Connect."
            }
        } catch {
            purchaseError = "Failed to load products: \(error.localizedDescription)"
        }
    }

    func checkEntitlement() async {
        proStatus = .loading
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            guard Self.allProductIDs.contains(transaction.productID) else { continue }
            if transaction.revocationDate != nil { continue }
            if let expiration = transaction.expirationDate, expiration < Date() { continue }
            proStatus = .purchased
            return
        }
        proStatus = .notPurchased
    }

    // Legacy entry point used elsewhere — defaults to the lifetime tier.
    func purchase() async {
        await purchase(tier: .lifetime)
    }

    func purchase(tier: ProTier) async {
        guard let product = product(for: tier) else {
            purchaseError = "Product not available."
            return
        }

        do {
            let result = try await product.purchase()

            switch result {
            case .success(let verification):
                guard case .verified(let transaction) = verification else {
                    purchaseError = StoreError.failedVerification.localizedDescription
                    return
                }
                proStatus = .purchased
                purchaseError = nil
                await transaction.finish()

            case .userCancelled:
                purchaseError = nil

            case .pending:
                purchaseError = StoreError.pendingApproval.localizedDescription

            @unknown default:
                purchaseError = StoreError.unknown.localizedDescription
            }
        } catch {
            purchaseError = error.localizedDescription
        }
    }

    func restorePurchases() async {
        proStatus = .loading
        purchaseError = nil

        do {
            try await AppStore.sync()
            await checkEntitlement()
            if proStatus == .notPurchased {
                purchaseError = "No previous purchase found."
            }
        } catch {
            purchaseError = "Restore failed. Please try again."
        }
    }

    private func listenForTransactions() async {
        for await result in Transaction.updates {
            guard case .verified(let transaction) = result else { continue }
            guard Self.allProductIDs.contains(transaction.productID) else { continue }
            await checkEntitlement()
            await transaction.finish()
        }
    }
}
