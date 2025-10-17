//
//  KeyboardShortcutBridge.swift
//
//  Created by Eric Cai on 2025/09/22.
//

import AppKit
import SwiftUI

/// 将 SwiftUI 视图与全局 `KeyboardShortcutManager` 连接，确保多窗口模式下的快捷键处理。
struct KeyboardShortcutBridge: NSViewRepresentable {
  let handlerProvider: () -> (NSEvent) -> Bool
  let tokenUpdate: (UUID?) -> Void

  func makeNSView(context: Context) -> BridgeView {
    BridgeView(handlerProvider: handlerProvider, tokenUpdate: tokenUpdate)
  }

  func updateNSView(_ nsView: BridgeView, context: Context) {
    nsView.handlerProvider = handlerProvider
    nsView.tokenUpdate = tokenUpdate
    nsView.refreshRegistration()
  }

  // MARK: - Backing View
  final class BridgeView: NSView {
    var handlerProvider: () -> (NSEvent) -> Bool
    var tokenUpdate: (UUID?) -> Void
    private var token: UUID?

    init(handlerProvider: @escaping () -> (NSEvent) -> Bool, tokenUpdate: @escaping (UUID?) -> Void) {
      self.handlerProvider = handlerProvider
      self.tokenUpdate = tokenUpdate
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
      if newWindow == nil {
        tokenUpdate(nil)
      }
    }

    deinit {
      unregister()
    }

    func refreshRegistration() {
      guard let window else {
        tokenUpdate(nil)
        return
      }
      let handler = handlerProvider()
      if let token {
        KeyboardShortcutManager.shared.update(token: token, handler: handler)
        tokenUpdate(token)
      } else {
        let newToken = KeyboardShortcutManager.shared.register(window: window, handler: handler)
        token = newToken
        tokenUpdate(newToken)
      }
    }

    private func unregister() {
      if let token {
        KeyboardShortcutManager.shared.unregister(token: token)
        self.token = nil
        tokenUpdate(nil)
      }
    }
  }
}
