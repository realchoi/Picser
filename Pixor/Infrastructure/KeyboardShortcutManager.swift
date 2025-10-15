//
//  KeyboardShortcutManager.swift
//  Pixor
//
//  Created by Eric Cai on 2025/09/22.
//

import AppKit

/// 管理应用内所有窗口的键盘事件监视，以支持多窗口并发处理。
final class KeyboardShortcutManager {
  static let shared = KeyboardShortcutManager()

  private struct WindowInfo {
    weak var window: NSWindow?
    var handler: (NSEvent) -> Bool
    let token: UUID
  }

  private var windows: [ObjectIdentifier: WindowInfo] = [:]
  private var tokenLookup: [UUID: ObjectIdentifier] = [:]
  private var monitor: Any?
  private var observers: [NSObjectProtocol] = []
  private weak var activeWindow: NSWindow?

  private init() {
    startMonitorIfNeeded()
    observeWindowLifecycle()
  }

  deinit {
    stopMonitor()
    removeObservers()
  }

  /// 注册指定窗口的键盘处理闭包，返回用于注销的 token。
  @MainActor
  @discardableResult
  func register(window: NSWindow, handler: @escaping (NSEvent) -> Bool) -> UUID {
    cleanupEntries()
    let id = ObjectIdentifier(window)

    if var info = windows[id] {
      info.window = window
      info.handler = handler
      windows[id] = info
      tokenLookup[info.token] = id
      if window === NSApp.keyWindow {
        activeWindow = window
      }
      startMonitorIfNeeded()
      return info.token
    }

    let token = UUID()
    windows[id] = WindowInfo(window: window, handler: handler, token: token)
    tokenLookup[token] = id
    if window === NSApp.keyWindow {
      activeWindow = window
    }
    startMonitorIfNeeded()
    return token
  }

  /// 更新注册的快捷键回调。
  @MainActor
  func update(token: UUID, handler: @escaping (NSEvent) -> Bool) {
    cleanupEntries()
    guard let id = tokenLookup[token], var info = windows[id] else { return }
    info.handler = handler
    windows[id] = info
  }

  /// 根据注册 token 返回对应窗口
  @MainActor
  func window(for token: UUID) -> NSWindow? {
    cleanupEntries()
    guard let id = tokenLookup[token], let info = windows[id] else { return nil }
    return info.window
  }

  /// 注销此前注册的窗口快捷键回调。
  @MainActor
  func unregister(token: UUID) {
    if let id = tokenLookup[token] {
      windows.removeValue(forKey: id)
      tokenLookup.removeValue(forKey: token)
    }
    cleanupEntries()
    if windows.isEmpty {
      stopMonitor()
    }
  }

  // MARK: - Monitor lifecycle

  private func startMonitorIfNeeded() {
    guard monitor == nil else { return }
    monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
      guard let self else { return event }
      return self.handle(event: event)
    }
  }

  private func stopMonitor() {
    if let monitor {
      NSEvent.removeMonitor(monitor)
      self.monitor = nil
    }
  }

  private func observeWindowLifecycle() {
    let nc = NotificationCenter.default
    let becomeObs = nc.addObserver(forName: NSWindow.didBecomeKeyNotification, object: nil, queue: nil) { [weak self] notif in
      guard let self, let window = notif.object as? NSWindow else { return }
      self.activeWindow = window
    }
    let resignObs = nc.addObserver(forName: NSWindow.didResignKeyNotification, object: nil, queue: nil) { [weak self] notif in
      guard let self, let window = notif.object as? NSWindow else { return }
      if self.activeWindow === window {
        self.activeWindow = nil
      }
    }
    let closeObs = nc.addObserver(forName: NSWindow.willCloseNotification, object: nil, queue: nil) { [weak self] notif in
      guard let window = notif.object as? NSWindow else { return }
      Task { @MainActor in
        guard let self else { return }
        self.removeEntries(for: window)
      }
    }
    observers.append(contentsOf: [becomeObs, resignObs, closeObs])
  }

  private func removeObservers() {
    let nc = NotificationCenter.default
    observers.forEach { nc.removeObserver($0) }
    observers.removeAll()
  }

  // MARK: - Event routing

  private func handle(event: NSEvent) -> NSEvent? {
    guard event.type == .keyDown else { return event }

    cleanupEntries()

    guard let window = event.window ?? NSApp.keyWindow else {
      return event
    }

    guard shouldHandle(event: event, in: window) else {
      return event
    }

    activeWindow = window

    guard let handler = handler(for: window) else {
      return event
    }

    return handler(event) ? nil : event
  }

  private func handler(for window: NSWindow) -> ((NSEvent) -> Bool)? {
    let id = ObjectIdentifier(window)
    return windows[id]?.handler
  }

  @MainActor
  private func removeEntries(for window: NSWindow) {
    let id = ObjectIdentifier(window)
    if let info = windows.removeValue(forKey: id) {
      tokenLookup.removeValue(forKey: info.token)
    }
    if windows.isEmpty {
      stopMonitor()
    }
  }

  private func shouldHandle(event: NSEvent, in window: NSWindow) -> Bool {
    if window.attachedSheet != nil { return false }
    if NSApp.modalWindow != nil { return false }

    if let responder = window.firstResponder {
      if responder is NSTextView { return false }
      if let view = responder as? NSView, view.enclosingMenuItem != nil {
        return false
      }
    }

    return true
  }

  private func cleanupEntries() {
    var toRemove: [ObjectIdentifier] = []
    for (id, info) in windows {
      guard info.window != nil else {
        toRemove.append(id)
        continue
      }
      tokenLookup[info.token] = id
    }
    for id in toRemove {
      if let info = windows.removeValue(forKey: id) {
        tokenLookup.removeValue(forKey: info.token)
      }
    }
  }
}
