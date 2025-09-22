//
//  KeyboardShortcutHandler.swift
//  Pixor
//
//  Created by Codex on 2025/03/10.
//

import AppKit
import SwiftUI

/// 负责处理 ContentView 级别的键盘事件，将视图状态读写逻辑和事件解析解耦。
struct KeyboardShortcutHandler {
  let appSettings: AppSettings
  let imageURLs: () -> [URL]
  let selectedImageURL: () -> URL?
  let setSelectedImage: (URL) -> Void
  let showingExifInfo: () -> Bool
  let setShowingExifInfo: (Bool) -> Void

  func handle(event: NSEvent) -> Bool {
    assert(Thread.isMainThread)
    guard event.type == .keyDown else { return false }
    guard shouldHandle(event) else { return false }
    guard let key = keyEquivalent(from: event) else { return false }
    return dispatch(key: key)
  }

  private func shouldHandle(_ event: NSEvent) -> Bool {
    let disallowedModifiers: NSEvent.ModifierFlags = [.command, .control, .option]
    return event.modifierFlags.intersection(disallowedModifiers).isEmpty
  }

  private func keyEquivalent(from event: NSEvent) -> KeyEquivalent? {
    if let special = event.specialKey {
      switch special {
      case .leftArrow: return .leftArrow
      case .rightArrow: return .rightArrow
      case .upArrow: return .upArrow
      case .downArrow: return .downArrow
      case .pageUp: return .pageUp
      case .pageDown: return .pageDown
      case .home: return .home
      case .end: return .end
      default:
        break
      }
    }

    if event.keyCode == 53 { // ESC
      return .escape
    }

    if let chars = event.charactersIgnoringModifiers, let first = chars.first {
      return KeyEquivalent(first)
    }

    return nil
  }

  private func dispatch(key: KeyEquivalent) -> Bool {
    assert(Thread.isMainThread)
    if key == .escape {
      if showingExifInfo() {
        setShowingExifInfo(false)
        return true
      }
      return false
    }

    let urls = imageURLs()
    guard !urls.isEmpty, let current = selectedImageURL() else {
      return false
    }

    guard let currentIndex = urls.firstIndex(of: current) else {
      return false
    }

    guard let targetIndex = ImageNavigation.nextIndex(
      for: key,
      mode: appSettings.imageNavigationKey,
      currentIndex: currentIndex,
      totalCount: urls.count
    ) else {
      return false
    }

    guard urls.indices.contains(targetIndex) else { return false }
    setSelectedImage(urls[targetIndex])
    return true
  }
}
