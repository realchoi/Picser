#if os(macOS)
import AppKit
import SwiftUI

/// 统一管理购买弹窗的展示与错误提示，避免各调用点散落处理
@MainActor
final class PurchaseFlowCoordinator {
  static let shared = PurchaseFlowCoordinator()

  private let panelPresenter = PurchaseInfoPanelPresenter()
  private var dismissHandler: (() -> Void)?
  private var restoreInProgress = false

  private init() {}

  func present(
    context: UpgradePromptContext,
    purchaseManager: PurchaseManager,
    onPurchase: @escaping (PurchaseProductKind) -> Void,
    onRestore: @escaping () -> Void,
    onRefreshReceipt: @escaping () -> Void,
    onDismiss: @escaping () -> Void
  ) {
    dismissHandler = onDismiss

    let anchorWindow = NSApp.keyWindow ?? NSApp.mainWindow ?? NSApp.windows.first(where: { $0.isVisible && !$0.isKind(of: NSPanel.self) })

    panelPresenter.present(
      context: context,
      purchaseManager: purchaseManager,
      anchorWindow: anchorWindow,
      onPurchase: onPurchase,
      onRestore: onRestore,
      onRefreshReceipt: onRefreshReceipt,
      onDismissRequested: { [weak self] in
        self?.handleDismiss()
      }
    )
  }

  func dismiss() {
    guard panelPresenter.isPresenting else { return }
    panelPresenter.dismiss()
    // handleDismiss 将在 windowWillClose 中被调用
  }

  func presentError(title: String, message: String, fallback: @escaping () -> Void) {
    if panelPresenter.isPresenting {
      panelPresenter.presentError(title: title, message: message)
    } else {
      fallback()
    }
  }

  var isPresenting: Bool {
    panelPresenter.isPresenting
  }

  func tryBeginRestore() -> Bool {
    guard !restoreInProgress else { return false }
    restoreInProgress = true
    return true
  }

  func endRestore() {
    restoreInProgress = false
  }

  private func handleDismiss() {
    restoreInProgress = false
    dismissHandler?()
    dismissHandler = nil
  }
}
#else
import SwiftUI

@MainActor
final class PurchaseFlowCoordinator {
  static let shared = PurchaseFlowCoordinator()
  private init() {}

  func present(
    context: UpgradePromptContext,
    purchaseManager: PurchaseManager,
    onPurchase: @escaping (PurchaseProductKind) -> Void,
    onRestore: @escaping () -> Void,
    onRefreshReceipt: @escaping () -> Void,
    onDismiss: @escaping () -> Void
  ) {
    onDismiss()
  }

  func dismiss() {}

  func presentError(title: String, message: String, fallback: @escaping () -> Void) {
    fallback()
  }

  var isPresenting: Bool { false }
}
#endif
