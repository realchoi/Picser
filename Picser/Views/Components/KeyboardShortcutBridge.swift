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
  let tokenUpdate: (Any?) -> Void  // 改为Any，支持NSWindow或UUID
  let shouldRegisterHandler: () -> Bool  // 检查是否应该注册键盘事件

  func makeNSView(context: Context) -> BridgeView {
    BridgeView(
      handlerProvider: handlerProvider,
      tokenUpdate: tokenUpdate,
      shouldRegisterHandler: shouldRegisterHandler
    )
  }

  func updateNSView(_ nsView: BridgeView, context: Context) {
    nsView.handlerProvider = handlerProvider
    nsView.tokenUpdate = tokenUpdate
    nsView.shouldRegisterHandler = shouldRegisterHandler
    nsView.refreshRegistration()
  }

  // MARK: - Backing View
  final class BridgeView: NSView {
    var handlerProvider: () -> (NSEvent) -> Bool
    var tokenUpdate: (Any?) -> Void  // 改为Any，支持NSWindow或UUID
    var shouldRegisterHandler: () -> Bool  // 新增：检查是否应该注册键盘事件
    private var token: UUID?

    init(handlerProvider: @escaping () -> (NSEvent) -> Bool,
         tokenUpdate: @escaping (Any?) -> Void,
         shouldRegisterHandler: @escaping () -> Bool) {
      self.handlerProvider = handlerProvider
      self.tokenUpdate = tokenUpdate
      self.shouldRegisterHandler = shouldRegisterHandler
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

      // 只有当ContentView有图片内容时，才注册键盘事件
      if !shouldRegisterHandler() {
        // 如果之前注册过，现在需要注销
        if let token {
          KeyboardShortcutManager.shared.unregister(token: token)
          self.token = nil
        }
        tokenUpdate(nil)
        return
      }

      let handler = handlerProvider()
      if let token {
        KeyboardShortcutManager.shared.update(token: token, handler: handler)
        // 传递NSWindow实例给ContentView
        tokenUpdate(window)
      } else {
        let newToken = KeyboardShortcutManager.shared.register(window: window, handler: handler)
        token = newToken
        // 传递NSWindow实例给ContentView
        tokenUpdate(window)
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
