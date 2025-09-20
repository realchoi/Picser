//
//  ScrollWheelHandler.swift
//  Pixor
//
//  Extracted from ZoomableImageView.
//

import AppKit
import SwiftUI

/// 滚轮事件处理器
struct ScrollWheelHandler: NSViewRepresentable {
  let onScrollWheel: (Double) -> Void

  func makeNSView(context: Context) -> ScrollWheelView {
    let view = ScrollWheelView()
    view.onScrollWheel = onScrollWheel
    return view
  }

  func updateNSView(_ nsView: ScrollWheelView, context: Context) {
    nsView.onScrollWheel = onScrollWheel
  }
}

/// 处理滚轮事件的NSView
class ScrollWheelView: NSView {
  var onScrollWheel: ((Double) -> Void)?

  override func scrollWheel(with event: NSEvent) {
    // 使用正确方向的滚轮处理
    let deltaY = event.scrollingDeltaY
    onScrollWheel?(deltaY * 0.01)  // 移除负号，使缩放方向正确
  }

  override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
    return true
  }

  override var acceptsFirstResponder: Bool {
    return true
  }

  override func becomeFirstResponder() -> Bool {
    return true
  }
}

