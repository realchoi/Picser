import Foundation

/// 升级提示上下文，区分不同功能入口的购买提示场景
enum UpgradePromptContext: String, Identifiable {
  case transform
  case crop
  case exif
  case slideshow
  case generic
  case purchase

  var id: String { rawValue }

  var message: String {
    L10n.string("unlock_alert_body_generic")
  }
}
