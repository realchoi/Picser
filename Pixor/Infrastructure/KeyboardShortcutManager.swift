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

  private struct Entry {
    weak var window: NSWindow?
    var handler: (NSEvent) -> Bool
  }

  private var entries: [UUID: Entry] = [:]
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
    let token = UUID()
    entries[token] = Entry(window: window, handler: handler)
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
    guard var entry = entries[token] else { return }
    entry.handler = handler
    entries[token] = entry
  }

  /// 注销此前注册的窗口快捷键回调。
  @MainActor
  func unregister(token: UUID) {
    entries.removeValue(forKey: token)
    cleanupEntries()
    if entries.isEmpty {
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
      guard let self, let window = notif.object as? NSWindow else { return }
      self.removeEntries(for: window)
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
    for entry in entries.values {
      if let entryWindow = entry.window, entryWindow === window {
        return entry.handler
      }
    }
    return nil
  }

  @MainActor
  private func removeEntries(for window: NSWindow) {
    entries = entries.filter { _, entry in
      guard let entryWindow = entry.window else { return false }
      return entryWindow !== window
    }
    if entries.isEmpty {
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
    entries = entries.filter { _, entry in
      guard let entryWindow = entry.window else { return false }
      return entryWindow.isVisible
    }
  }
}
