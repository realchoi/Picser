import StoreKit

/// 监听与处理 StoreKit 事务更新的小型协作者
struct PurchaseTransactionMonitor {
  func observeUpdates(for productIDs: Set<String>, handler: @escaping (Transaction) async -> Void) -> Task<Void, Never> {
    Task(priority: .background) {
      for await update in Transaction.updates {
        guard let transaction = try? PurchaseTransactionMonitor.checkVerified(update) else { continue }
        guard productIDs.contains(transaction.productID) else { continue }
        await handler(transaction)
      }
    }
  }

  func iterateCurrentEntitlements(for productIDs: Set<String>, handler: @escaping (Transaction) async -> Void) async {
    for await result in Transaction.currentEntitlements {
      guard let transaction = try? PurchaseTransactionMonitor.checkVerified(result) else { continue }
      guard productIDs.contains(transaction.productID) else { continue }
      await handler(transaction)
    }
  }

  static func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
    switch result {
    case .verified(let safe):
      return safe
    case .unverified:
      throw PurchaseManagerError.failedVerification
    }
  }
}
