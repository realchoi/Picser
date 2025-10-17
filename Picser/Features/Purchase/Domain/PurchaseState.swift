import Foundation

/// 描述应用内购权益的聚合状态
enum PurchaseState: Equatable {
  case unknown
  case onboarding
  case trial(TrialStatus)
  case trialExpired(TrialStatus)
  case subscriber(SubscriptionStatus)
  case subscriberLapsed(SubscriptionStatus)
  case lifetime(LifetimeStatus)
  case revoked(PurchaseRevocationReason)
}

/// 试用状态元数据
struct TrialStatus: Equatable {
  let startDate: Date
  let endDate: Date
}

/// 订阅状态元数据
struct SubscriptionStatus: Equatable {
  let productID: String
  let transactionID: String?
  let expirationDate: Date?
  let isInGracePeriod: Bool
}

/// 买断状态元数据
struct LifetimeStatus: Equatable {
  let productID: String
  let transactionID: String?
  let purchaseDate: Date
}

/// 撤销原因
enum PurchaseRevocationReason: Equatable {
  case refunded
  case validationFailed
  case developerAction
  case unknown
}
