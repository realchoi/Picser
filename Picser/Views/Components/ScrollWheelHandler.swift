//
//  ScrollWheelHandler.swift
//
//  Extracted from ZoomableImageView.
//

import AppKit
import SwiftUI

/// 滚轮事件处理器
struct ScrollWheelHandler: NSViewRepresentable {
  let onScrollWheel: (Double, CGPoint) -> Void

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
  var onScrollWheel: ((Double, CGPoint) -> Void)?
  private var scrollMonitor: Any?
  private var lastHandledEventTimestamp: TimeInterval?
  override var isFlipped: Bool { true }

  override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
    return true
  }

  override var acceptsFirstResponder: Bool {
    return true
  }

  override func becomeFirstResponder() -> Bool {
    return true
  }

  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    installScrollMonitor()
  }

  override func viewWillMove(toWindow newWindow: NSWindow?) {
    if newWindow == nil {
      removeScrollMonitor()
    }
    super.viewWillMove(toWindow: newWindow)
  }

  deinit {
    removeScrollMonitor()
  }

  override func scrollWheel(with event: NSEvent) {
    if let last = lastHandledEventTimestamp, abs(last - event.timestamp) < 0.0001 {
      return
    }
    let deltaY = event.scrollingDeltaY
    let locationInView = convert(event.locationInWindow, from: nil)
    onScrollWheel?(deltaY * 0.01, locationInView)
    lastHandledEventTimestamp = event.timestamp
  }

  private func installScrollMonitor() {
    removeScrollMonitor()
    scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
      guard let self, let window = self.window, event.window == window else { return event }
      let locationInView = self.convert(event.locationInWindow, from: nil)
      if self.bounds.contains(locationInView) {
        self.onScrollWheel?(event.scrollingDeltaY * 0.01, locationInView)
        self.lastHandledEventTimestamp = event.timestamp
        return nil
      }
      return event
    }
  }

  private func removeScrollMonitor() {
    if let monitor = scrollMonitor {
      NSEvent.removeMonitor(monitor)
      scrollMonitor = nil
    }
  }
}
