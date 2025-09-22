import Foundation

/// 内购流程可能抛出的错误
enum PurchaseManagerError: LocalizedError {
  case productUnavailable
  case failedVerification
  case purchaseCancelled
  case purchasePending
  case restoreFailed
  case unknown(Error)

  var errorDescription: String? {
    switch self {
    case .productUnavailable:
      return "purchase_error_product_unavailable".localized
    case .failedVerification:
      return "purchase_error_failed_verification".localized
    case .purchaseCancelled:
      return "purchase_error_cancelled".localized
    case .purchasePending:
      return "purchase_error_pending".localized
    case .restoreFailed:
      return "purchase_error_restore_failed".localized
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
