#if os(macOS)
import AppKit
import SwiftUI

/// 负责管理购买信息窗口的展示，确保界面以浮动面板形式覆盖应用窗口
final class PurchaseInfoPanelPresenter: NSObject, NSWindowDelegate {
  private var panel: NSPanel?
  private var hostingController: NSHostingController<PurchaseInfoPanelContent>?
  private var externalDismiss: (() -> Void)?
  private weak var parentWindow: NSWindow?

  var isPresenting: Bool {
    panel != nil
  }

  @MainActor
  func present(
    context: UpgradePromptContext,
    purchaseManager: PurchaseManager,
    anchorWindow: NSWindow? = nil,
    onPurchase: @escaping (PurchaseProductKind) -> Void,
    onRestore: @escaping () -> Void,
    onRefreshReceipt: @escaping () -> Void,
    onDismissRequested: @escaping () -> Void
  ) {
    let rootView = PurchaseInfoPanelContent(
      purchaseManager: purchaseManager,
      context: context,
      onPurchase: onPurchase,
      onRestore: onRestore,
      onRefreshReceipt: onRefreshReceipt,
      onClose: { [weak self] in self?.dismiss() }
    )

    if hostingController == nil || panel == nil {
      let controller = NSHostingController(rootView: rootView)
      let panel = makePanel()
      panel.contentViewController = controller
      panel.delegate = self

      updateParentWindow(to: anchorWindow, panel: panel)
      center(panel: panel, relativeTo: anchorWindow)
      panel.makeKeyAndOrderFront(nil)

      hostingController = controller
      self.panel = panel
    } else if let existingPanel = panel {
      hostingController?.rootView = rootView
      updateParentWindow(to: anchorWindow, panel: existingPanel)
      center(panel: existingPanel, relativeTo: anchorWindow)
      existingPanel.makeKeyAndOrderFront(nil)
    }

    externalDismiss = onDismissRequested
    NSApp.activate(ignoringOtherApps: true)
  }

  @MainActor
  func dismiss() {
    if let parentWindow, let panel {
      parentWindow.removeChildWindow(panel)
    }
    parentWindow = nil
    panel?.close()
  }

  func windowWillClose(_ notification: Notification) {
    if let parentWindow, let panel {
      parentWindow.removeChildWindow(panel)
    }
    hostingController = nil
    panel = nil
    parentWindow = nil
    externalDismiss?()
    externalDismiss = nil
  }

  @MainActor
  func presentError(title: String, message: String) {
    guard let panel else { return }

    let alert = NSAlert()
    alert.alertStyle = .warning
    alert.messageText = title
    alert.informativeText = message
    alert.addButton(withTitle: "ok_button".localized)
    alert.beginSheetModal(for: panel)
  }

  private func updateParentWindow(to newParent: NSWindow?, panel: NSPanel) {
    if parentWindow === newParent { return }
    if let parentWindow, parentWindow.childWindows?.contains(panel) == true {
      parentWindow.removeChildWindow(panel)
    }
    parentWindow = newParent
    newParent?.addChildWindow(panel, ordered: .above)
  }

  private func center(panel: NSPanel, relativeTo window: NSWindow?) {
    guard let baseWindow = window ?? parentWindow ?? NSApp.keyWindow ?? NSApp.mainWindow else {
      panel.center()
      return
    }

    var origin = NSPoint(
      x: baseWindow.frame.midX - panel.frame.width / 2,
      y: baseWindow.frame.midY - panel.frame.height / 2
    )

    if let screen = baseWindow.screen ?? panel.screen ?? NSScreen.main {
      let visible = screen.visibleFrame
      origin.x = min(max(origin.x, visible.minX), visible.maxX - panel.frame.width)
      origin.y = min(max(origin.y, visible.minY), visible.maxY - panel.frame.height)
    }

    panel.setFrameOrigin(origin)
  }

  private func makePanel() -> NSPanel {
    let panel = NSPanel(
      contentRect: NSRect(x: 0, y: 0, width: 520, height: 600),
      styleMask: [.titled, .closable, .fullSizeContentView],
      backing: .buffered,
      defer: false
    )
    panel.titleVisibility = .hidden
    panel.titlebarAppearsTransparent = true
    panel.hidesOnDeactivate = true
    panel.collectionBehavior = [.fullScreenAuxiliary]
    panel.hasShadow = true
    panel.isReleasedWhenClosed = false
    panel.isMovableByWindowBackground = true
    panel.standardWindowButton(.closeButton)?.isHidden = true
    panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
    panel.standardWindowButton(.zoomButton)?.isHidden = true
    panel.animationBehavior = .documentWindow
    return panel
  }
}

private struct PurchaseInfoPanelContent: View {
  let purchaseManager: PurchaseManager
  let context: UpgradePromptContext
  let onPurchase: (PurchaseProductKind) -> Void
  let onRestore: () -> Void
  let onRefreshReceipt: () -> Void
  let onClose: () -> Void

  var body: some View {
    PurchaseInfoView(
      context: context,
      onPurchase: onPurchase,
      onRestore: onRestore,
      onRefreshReceipt: onRefreshReceipt,
      onClose: onClose
    )
    .environmentObject(purchaseManager)
  }
}
#endif
