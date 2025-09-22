import Foundation

/// 升级提示上下文，区分不同功能入口的购买提示场景
enum UpgradePromptContext: String, Identifiable {
  case transform
  case crop
  case generic
  case purchase

  var id: String { rawValue }

  var message: String {
    switch self {
    case .transform:
      return "unlock_alert_body_transform".localized
    case .crop:
      return "unlock_alert_body_crop".localized
    case .generic:
      return "unlock_alert_body_generic".localized
    case .purchase:
      return "unlock_alert_body_manual_purchase".localized
    }
  }
}
