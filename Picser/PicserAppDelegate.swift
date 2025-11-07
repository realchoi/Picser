//
//  PicserAppDelegate.swift
//
//  Created by Eric Cai on 2025/10/09.
//

import AppKit

@MainActor
final class PicserAppDelegate: NSObject, NSApplicationDelegate {
  var externalOpenCoordinator: ExternalOpenCoordinator?

  func configure(externalOpenCoordinator: ExternalOpenCoordinator) {
    self.externalOpenCoordinator = externalOpenCoordinator
  }

  func application(_ application: NSApplication, open urls: [URL]) {
    // 如果有多个窗口，只保留keyWindow，其他窗口关闭
    let visibleWindows = NSApp.windows.filter { $0.isVisible }
    if visibleWindows.count > 1 {
      for (i, window) in visibleWindows.enumerated() {
        if i > 0 {  // 保留第1个窗口，关闭其他的
          window.close()
        }
      }
    }

    // 异步调用handleIncoming
    Task {
      await externalOpenCoordinator?.handleIncoming(urls: urls)
    }
  }

  func application(_ sender: NSApplication, openFile filename: String) -> Bool {
    guard let coordinator = externalOpenCoordinator else { return false }
    let url = URL(fileURLWithPath: filename)
    Task {
      await coordinator.handleIncoming(urls: [url])
    }
    return true
  }
}
