import Foundation

/// 统一管理内购商品与试用期配置
struct PurchaseConfiguration {
  let subscription: PurchaseProductConfiguration?
  let lifetime: PurchaseProductConfiguration?
  let trialDuration: TimeInterval

  init(subscription: PurchaseProductConfiguration?, lifetime: PurchaseProductConfiguration?, trialDuration: TimeInterval) {
    self.subscription = subscription
    self.lifetime = lifetime
    self.trialDuration = trialDuration
  }

  var allProductConfigurations: [PurchaseProductConfiguration] {
    [subscription, lifetime].compactMap { $0 }
  }

  func configuration(for productID: String) -> PurchaseProductConfiguration? {
    allProductConfigurations.first { $0.identifier == productID }
  }
}

extension PurchaseConfiguration {
  static func loadDefault(trialDays: Int = 7) -> PurchaseConfiguration {
    let lifetimeIdentifier = PurchaseSecretsProvider.purchaseLifetimeIdentifier()
    let subscriptionIdentifier = PurchaseSecretsProvider.purchaseSubscriptionIdentifier()

    let trialDuration = TimeInterval(trialDays * 24 * 60 * 60)

    let lifetimeConfig = PurchaseProductConfiguration(
      identifier: lifetimeIdentifier,
      kind: .lifetime,
      introductoryTrialDuration: nil
    )

    let subscriptionConfig = PurchaseProductConfiguration(
      identifier: subscriptionIdentifier,
      kind: .subscription,
      introductoryTrialDuration: trialDuration
    )

    return PurchaseConfiguration(
      subscription: subscriptionConfig,
      lifetime: lifetimeConfig,
      trialDuration: trialDuration
    )
  }
}
