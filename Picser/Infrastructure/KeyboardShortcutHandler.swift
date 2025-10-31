//
//  KeyboardShortcutHandler.swift
//
//  Created by Eric Cai on 2025/09/22.
//

import AppKit
import SwiftUI
import KeyboardShortcuts

/// 负责处理 ContentView 级别的键盘事件，将视图状态读写逻辑和事件解析解耦。
struct KeyboardShortcutHandler {
  let appSettings: AppSettings
  let imageURLs: () -> [URL]
  let selectedImageURL: () -> URL?
  let setSelectedImage: (URL) -> Void
  let showingExifInfo: () -> Bool
  let setShowingExifInfo: (Bool) -> Void
  let performDelete: () -> Bool
  let rotateCounterclockwise: () -> Void
  let rotateClockwise: () -> Void
  let mirrorHorizontal: () -> Void
  let mirrorVertical: () -> Void
  let resetTransform: () -> Void

  func handle(event: NSEvent) -> Bool {
    assert(Thread.isMainThread)
    guard event.type == .keyDown else { return false }

    if event.keyCode == 53 { // Escape
      if showingExifInfo() {
        setShowingExifInfo(false)
        return true
      }
      return false
    }

    guard let eventShortcut = KeyboardShortcuts.Shortcut(event: event) else {
      return false
    }

    if matches(action: .deletePrimary, eventShortcut) || matches(action: .deleteSecondary, eventShortcut) {
      return performDelete()
    }

    if matches(action: .rotateCounterclockwise, eventShortcut) {
      rotateCounterclockwise()
      return true
    }

    if matches(action: .rotateClockwise, eventShortcut) {
      rotateClockwise()
      return true
    }

    if matches(action: .mirrorHorizontal, eventShortcut) {
      mirrorHorizontal()
      return true
    }

    if matches(action: .mirrorVertical, eventShortcut) {
      mirrorVertical()
      return true
    }

    if matches(action: .resetTransform, eventShortcut) {
      resetTransform()
      return true
    }

    if matches(action: .navigatePrevious, eventShortcut) {
      return navigate(offset: -1)
    }

    if matches(action: .navigateNext, eventShortcut) {
      return navigate(offset: 1)
    }

    return false
  }

  /// 判断输入事件是否匹配指定动作的快捷键。
  private func matches(action: ShortcutAction, _ eventShortcut: KeyboardShortcuts.Shortcut) -> Bool {
    guard let configured = appSettings.shortcut(for: action) else {
      return false
    }
    return configured == eventShortcut
  }

  /// 根据偏移值进行图片导航，成功时返回 true。
  private func navigate(offset: Int) -> Bool {
    let urls = imageURLs()
    guard let current = selectedImageURL(),
          let currentIndex = urls.firstIndex(of: current),
          urls.count > 1 else {
      return false
    }

    let newIndex = (currentIndex + offset + urls.count) % urls.count
    guard newIndex != currentIndex else { return false }
    setSelectedImage(urls[newIndex])
    return true
  }
}
