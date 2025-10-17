import Foundation

/// 内购流程可能抛出的错误
enum PurchaseManagerError: LocalizedError {
  case productUnavailable
  case failedVerification
  case purchaseCancelled
  case purchasePending
  case restoreFailed
  case receiptRefreshFailed
  case unknown(Error)

  var errorDescription: String? {
    switch self {
    case .productUnavailable:
      return L10n.string("purchase_error_product_unavailable")
    case .failedVerification:
      return L10n.string("purchase_error_failed_verification")
    case .purchaseCancelled:
      return L10n.string("purchase_error_cancelled")
    case .purchasePending:
      return L10n.string("purchase_error_pending")
    case .restoreFailed:
      return L10n.string("purchase_error_restore_failed")
    case .receiptRefreshFailed:
      return L10n.string("purchase_error_receipt_refresh_failed")
    case .unknown(let error):
      return error.localizedDescription
    }
  }

  var shouldSuppressAlert: Bool {
    if case .purchaseCancelled = self {
      return true
    }
    return false
  }
}
