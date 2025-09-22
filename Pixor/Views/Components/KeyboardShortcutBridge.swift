//
//  KeyboardShortcutBridge.swift
//  Pixor
//
//  Created by Codex on 2025/03/10.
//

import AppKit
import SwiftUI

/// 将 SwiftUI 视图与全局 `KeyboardShortcutManager` 连接，确保多窗口模式下的快捷键处理。
struct KeyboardShortcutBridge: NSViewRepresentable {
  let handlerProvider: () -> (NSEvent) -> Bool

  func makeNSView(context: Context) -> BridgeView {
    BridgeView(handlerProvider: handlerProvider)
  }

  func updateNSView(_ nsView: BridgeView, context: Context) {
    nsView.handlerProvider = handlerProvider
    nsView.refreshRegistration()
  }

  // MARK: - Backing View
  final class BridgeView: NSView {
    var handlerProvider: () -> (NSEvent) -> Bool
    private var token: UUID?

    init(handlerProvider: @escaping () -> (NSEvent) -> Bool) {
      self.handlerProvider = handlerProvider
      super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
      fatalError("init(coder:) has not been implemented")
    }

    override func viewDidMoveToWindow() {
      super.viewDidMoveToWindow()
      refreshRegistration()
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
      super.viewWillMove(toWindow: newWindow)
      if window != nil {
        unregister()
      }
    }

    deinit {
      unregister()
    }

    func refreshRegistration() {
      guard let window else { return }
      let handler = handlerProvider()
      if let token {
        KeyboardShortcutManager.shared.update(token: token, handler: handler)
      } else {
        token = KeyboardShortcutManager.shared.register(window: window, handler: handler)
      }
    }

    private func unregister() {
      if let token {
        KeyboardShortcutManager.shared.unregister(token: token)
        self.token = nil
      }
    }
  }
}
