import Foundation

/// 功能权限枚举：描述需要检验的功能点
enum AppFeature: Hashable {
  case transform
  case crop
  case generic
  case exif
  case slideshow
}

/// 功能访问策略：配置未购买用户可访问的功能集合
struct FeatureAccessPolicy {
  /// 默认策略：未购买用户无法访问受限功能
  static let standard = FeatureAccessPolicy(freeFeatures: [])

  let freeFeatures: Set<AppFeature>

  func allows(_ feature: AppFeature, isEntitled: Bool) -> Bool {
    isEntitled || freeFeatures.contains(feature)
  }
}

/// 统一的功能权限守卫，封装判定逻辑与升级提示触发
@MainActor
final class FeatureGatekeeper: ObservableObject {
  private let purchaseManager: PurchaseManager
  private let policy: FeatureAccessPolicy

  init(purchaseManager: PurchaseManager, policy: FeatureAccessPolicy = .standard) {
    self.purchaseManager = purchaseManager
    self.policy = policy
  }

  func hasAccess(to feature: AppFeature) -> Bool {
    policy.allows(feature, isEntitled: purchaseManager.isEntitled)
  }

  func perform(
    _ feature: AppFeature,
    context: UpgradePromptContext,
    requestUpgrade: (UpgradePromptContext) -> Void,
    action: () -> Void
  ) {
    if hasAccess(to: feature) {
      action()
    } else {
      requestUpgrade(context)
    }
  }
}
