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

@MainActor
@Observable
final class StoreManager {
    static let proUnlockID = "com.jackwallner.baseball.pro"

    private(set) var products: [Product] = []
    private(set) var proStatus: ProStatus = .loading
    private(set) var purchaseError: String?

    private var transactionListener: Task<Void, Never>?

    var proProduct: Product? {
        products.first { $0.id == Self.proUnlockID }
    }

    var proPrice: String {
        proProduct?.displayPrice ?? "$4.99"
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
            let ids: Set<String> = [Self.proUnlockID]
            products = try await Product.products(for: ids)
        } catch {
            purchaseError = "Could not load products."
        }
    }

    func checkEntitlement() async {
        proStatus = .loading
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            if transaction.productID == Self.proUnlockID {
                if transaction.revocationDate == nil {
                    proStatus = .purchased
                    return
                }
            }
        }
        proStatus = .notPurchased
    }

    func purchase() async {
        guard let product = proProduct else {
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
            if transaction.productID == Self.proUnlockID {
                if transaction.revocationDate == nil {
                    await MainActor.run { proStatus = .purchased }
                } else {
                    await MainActor.run { proStatus = .notPurchased }
                }
            }
            await transaction.finish()
        }
    }
}
