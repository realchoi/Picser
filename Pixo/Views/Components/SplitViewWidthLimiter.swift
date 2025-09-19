//
//  SplitViewWidthLimiter.swift
//  Pixo
//
//  Created by Eric Cai on 2025/9/19.
//

import AppKit
import SwiftUI

/// 通过拦截 NSSplitViewDelegate 限制侧边栏宽度，避免用户将其无限放大
struct SplitViewWidthLimiter: NSViewRepresentable {
  var minWidth: CGFloat
  var maxWidth: CGFloat

  func makeCoordinator() -> Coordinator {
    Coordinator(minWidth: minWidth, maxWidth: maxWidth)
  }

  func makeNSView(context: Context) -> NSView {
    let view = NSView()
    view.isHidden = true
    DispatchQueue.main.async {
      context.coordinator.attachIfNeeded(hostView: view)
    }
    return view
  }

  func updateNSView(_ nsView: NSView, context: Context) {
    context.coordinator.minWidth = minWidth
    context.coordinator.maxWidth = maxWidth
    context.coordinator.enforceCurrentConstraints()
  }

  final class Coordinator: NSObject, NSSplitViewDelegate {
    var minWidth: CGFloat
    var maxWidth: CGFloat
    private weak var splitView: NSSplitView?
    private weak var forwardingDelegate: NSSplitViewDelegate?

    init(minWidth: CGFloat, maxWidth: CGFloat) {
      self.minWidth = minWidth
      self.maxWidth = maxWidth
    }

    func attachIfNeeded(hostView: NSView) {
      guard splitView == nil else { return }
      guard let found = hostView.findEnclosingSplitView() else {
        DispatchQueue.main.async { [weak self, weak hostView] in
          guard let hostView else { return }
          self?.attachIfNeeded(hostView: hostView)
        }
        return
      }
      splitView = found
      forwardingDelegate = found.delegate
      found.delegate = self
      enforceCurrentConstraints()
    }

    func enforceCurrentConstraints() {
      guard let splitView, splitView.subviews.count > 0 else { return }
      let primary = splitView.subviews[0]
      let current = splitView.isVertical ? primary.frame.width : primary.frame.height
      let clamped = min(max(current, minWidth), maxWidth)
      guard abs(current - clamped) > 0.5 else { return }
      splitView.setPosition(clamped, ofDividerAt: 0)
    }

    // MARK: - NSSplitViewDelegate

    func splitView(
      _ splitView: NSSplitView,
      constrainMinCoordinate proposedMinimumPosition: CGFloat,
      ofSubviewAt dividerIndex: Int
    ) -> CGFloat {
      var value = proposedMinimumPosition
      if let forwardingDelegate,
         forwardingDelegate.responds(to: #selector(NSSplitViewDelegate.splitView(_:constrainMinCoordinate:ofSubviewAt:))) {
        value = forwardingDelegate.splitView?(
          splitView,
          constrainMinCoordinate: proposedMinimumPosition,
          ofSubviewAt: dividerIndex
        ) ?? proposedMinimumPosition
      }
      guard dividerIndex == 0 else { return value }
      return max(value, minWidth)
    }

    func splitView(
      _ splitView: NSSplitView,
      constrainMaxCoordinate proposedMaximumPosition: CGFloat,
      ofSubviewAt dividerIndex: Int
    ) -> CGFloat {
      var value = proposedMaximumPosition
      if let forwardingDelegate,
         forwardingDelegate.responds(to: #selector(NSSplitViewDelegate.splitView(_:constrainMaxCoordinate:ofSubviewAt:))) {
        value = forwardingDelegate.splitView?(splitView, constrainMaxCoordinate: proposedMaximumPosition, ofSubviewAt: dividerIndex) ?? proposedMaximumPosition
      }
      guard dividerIndex == 0 else { return value }
      return min(value, maxWidth)
    }

    override func responds(to aSelector: Selector!) -> Bool {
      if super.responds(to: aSelector) {
        return true
      }
      return forwardingDelegate?.responds(to: aSelector) ?? false
    }

    override func forwardingTarget(for aSelector: Selector!) -> Any? {
      if super.responds(to: aSelector) {
        return nil
      }
      return forwardingDelegate
    }
  }
}

private extension NSView {
  func findEnclosingSplitView() -> NSSplitView? {
    if let split = self as? NSSplitView {
      return split
    }
    return superview?.findEnclosingSplitView()
  }
}
