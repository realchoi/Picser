//
//  ContentView+Purchase.swift
//  Pixor
//
//  Created by Eric Cai on 2025/9/19.
//

import SwiftUI

/// 购买流程中的操作类型，便于呈现不同的错误文案
enum PurchaseFlowOperation {
  case purchase
  case restore

  var failureTitle: String {
    switch self {
    case .purchase:
      return "purchase_flow_purchase_failed_title".localized
    case .restore:
      return "purchase_flow_restore_failed_title".localized
    }
  }

  var debugLabel: String {
    switch self {
    case .purchase:
      return "purchase"
    case .restore:
      return "restore"
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
    if purchaseManager.isEntitled {
      action()
    } else {
      requestUpgrade(context)
    }
  }

  /// 异步弹出升级提示
  func requestUpgrade(_ context: UpgradePromptContext) {
    Task { @MainActor in
      upgradePromptContext = context
    }
  }

  func startPurchaseFlow(kind: PurchaseProductKind) {
    Task { @MainActor in
      do {
        try await purchaseManager.purchase(kind: kind)
        upgradePromptContext = nil
      } catch {
        let shouldDismiss = !((error as? PurchaseManagerError)?.shouldSuppressAlert ?? false)
        if shouldDismiss {
          upgradePromptContext = nil
        }
        handlePurchaseFlowError(error, operation: .purchase)
      }
    }
  }

  func startRestoreFlow() {
    Task { @MainActor in
      do {
        try await purchaseManager.restorePurchases()
        upgradePromptContext = nil
      } catch {
        let shouldDismiss = !((error as? PurchaseManagerError)?.shouldSuppressAlert ?? false)
        if shouldDismiss {
          upgradePromptContext = nil
        }
        handlePurchaseFlowError(error, operation: .restore)
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

    presentAlert(
      AlertContent(
        title: operation.failureTitle,
        message: error.purchaseDisplayMessage
      )
    )
  }
}
