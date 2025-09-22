//
//  WindowTrackerView.swift
//  Pixor
//
//  Created by Eric Cai on 2025/09/22.
//

import AppKit
import SwiftUI

/// 捕获当前 SwiftUI 视图所在的 NSWindow，并通过回调暴露给上层。
struct WindowTrackerView: NSViewRepresentable {
  let onResolve: (NSWindow?) -> Void

  func makeNSView(context: Context) -> TrackerNSView {
    let view = TrackerNSView()
    view.onResolve = onResolve
    return view
  }

  func updateNSView(_ nsView: TrackerNSView, context: Context) {
    nsView.onResolve = onResolve
    nsView.resolveWindow()
  }

  final class TrackerNSView: NSView {
    var onResolve: ((NSWindow?) -> Void)?

    override func viewDidMoveToWindow() {
      super.viewDidMoveToWindow()
      resolveWindow()
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
      super.viewWillMove(toWindow: newWindow)
      // 先将旧窗口置空，避免窗口关闭后引用失效
      if newWindow == nil {
        onResolve?(nil)
      }
    }

    func resolveWindow() {
      onResolve?(window)
    }
  }
}
