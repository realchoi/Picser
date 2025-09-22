import Foundation
import StoreKit

/// 内购商品的类型
enum PurchaseProductKind: Equatable {
  case subscription
  case lifetime
}

/// 描述一个待售商品的配置
struct PurchaseProductConfiguration: Equatable {
  let identifier: String
  let kind: PurchaseProductKind
  let introductoryTrialDuration: TimeInterval?

  init(identifier: String, kind: PurchaseProductKind, introductoryTrialDuration: TimeInterval? = nil) {
    self.identifier = identifier
    self.kind = kind
    self.introductoryTrialDuration = introductoryTrialDuration
  }
}

/// StoreKit 商品与领域配置的结合
struct PurchaseOffering: Identifiable, Equatable {
  let configuration: PurchaseProductConfiguration
  let product: Product

  var id: String { product.id }

  var kind: PurchaseProductKind { configuration.kind }
}
