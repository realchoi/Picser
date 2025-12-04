//
//  ContentView+Purchase.swift
//
//  Created by Eric Cai on 2025/9/19.
//

import SwiftUI

/// 购买流程中的操作类型，便于呈现不同的错误文案
enum PurchaseFlowOperation {
  case purchase
  case restore
  case refreshReceipt

  var failureTitle: String {
    switch self {
    case .purchase:
      return L10n.string("purchase_flow_purchase_failed_title")
    case .restore:
      return L10n.string("purchase_flow_restore_failed_title")
    case .refreshReceipt:
      return L10n.string("purchase_flow_refresh_failed_title")
    }
  }

  var debugLabel: String {
    switch self {
    case .purchase:
      return "purchase"
    case .restore:
      return "restore"
    case .refreshReceipt:
      return "refresh_receipt"
    }
  }
}

extension Error {
  /// 统一输出适合给用户查看的错误描述
  var purchaseDisplayMessage: String {
    if let localizedError = self as? LocalizedError,
       let description = localizedError.errorDescription,
       !description.isEmpty {
      return description
    }
    return localizedDescription
  }
}

extension ContentView {
  /// 根据购买权限执行操作，未授权时弹出升级提示
  func performIfEntitled(_ context: UpgradePromptContext, action: () -> Void) {
    let feature = context.mappedFeature
    featureGatekeeper.perform(
      feature,
      context: context,
      requestUpgrade: requestUpgrade,
      action: action
    )
  }

  /// 异步弹出升级提示
  func requestUpgrade(_ context: UpgradePromptContext) {
    Task { @MainActor in
      upgradePromptContext = context
      PurchaseFlowCoordinator.shared.present(
        context: context,
        purchaseManager: purchaseManager,
        onPurchase: { kind in
          self.startPurchaseFlow(kind: kind)
        },
        onRestore: {
          self.startRestoreFlow()
        },
        onRefreshReceipt: {
          self.startRefreshReceiptFlow()
        },
        onDismiss: {
          self.upgradePromptContext = nil
        }
      )
    }
  }

  func startPurchaseFlow(kind: PurchaseProductKind) {
    Task { @MainActor in
      do {
        try await purchaseManager.purchase(kind: kind)
        PurchaseFlowCoordinator.shared.dismiss()
        upgradePromptContext = nil
      } catch {
        handlePurchaseFlowError(error, operation: .purchase)
      }
    }
  }

  func startRestoreFlow() {
    guard PurchaseFlowCoordinator.shared.tryBeginRestore() else { return }

    Task { @MainActor in
      defer { PurchaseFlowCoordinator.shared.endRestore() }

      do {
        try await purchaseManager.restorePurchases()
        PurchaseFlowCoordinator.shared.dismiss()
        upgradePromptContext = nil
      } catch {
        handlePurchaseFlowError(error, operation: .restore)
      }
    }
  }

  func startRefreshReceiptFlow() {
    Task { @MainActor in
      do {
        try await purchaseManager.refreshReceipt()
      } catch {
        handlePurchaseFlowError(error, operation: .refreshReceipt)
      }
    }
  }

  @MainActor
  private func handlePurchaseFlowError(_ error: Error, operation: PurchaseFlowOperation) {
    if let managerError = error as? PurchaseManagerError, managerError.shouldSuppressAlert {
      // 用户主动取消时不额外提示
      return
    }

    #if DEBUG
    print("Purchase flow (\(operation.debugLabel)) failed: \(error.localizedDescription)")
    #endif

    PurchaseFlowCoordinator.shared.presentError(
      title: operation.failureTitle,
      message: error.purchaseDisplayMessage
    ) {
      self.presentAlert(
        AlertContent(
          title: operation.failureTitle,
          message: error.purchaseDisplayMessage
        )
      )
    }
  }
}

private extension UpgradePromptContext {
  var mappedFeature: AppFeature {
    switch self {
    case .transform:
      return .transform
    case .crop:
      return .crop
    case .exif:
      return .exif
    case .slideshow:
      return .slideshow
    case .tags:
      return .tags
    case .generic, .purchase:
      return .generic
    }
  }
}
