//
//  ZoomableContainerView.swift
//  PicTube
//
//  Created by Eric Cai on 2025/8/19.
//

import AppKit
import SwiftUI

struct ZoomableContainerView<Content: View>: NSViewRepresentable {
  // 通过 Binding 从父视图接收 scale 和 offset
  @Binding var scale: CGFloat
  @Binding var offset: CGSize
  let content: Content  // 要被包裹和缩放的 SwiftUI 视图

  // 添加 @ViewBuilder 初始化器
  init(scale: Binding<CGFloat>, offset: Binding<CGSize>, @ViewBuilder content: () -> Content) {
    self._scale = scale
    self._offset = offset
    self.content = content()
  }

  // MARK: - NSViewRepresentable Conformance

  func makeNSView(context: Context) -> CustomZoomableView<Content> {
    // 创建我们的自定义 NSView 实例
    let view = CustomZoomableView<Content>(frame: .zero)
    // 将 coordinator 赋值给 view，以便在 NSView 内部可以回调
    view.coordinator = context.coordinator

    // 创建一个 NSHostingView 来承载我们的 SwiftUI content
    let hostingView = NSHostingView(rootView: content)
    hostingView.translatesAutoresizingMaskIntoConstraints = false

    // It's good practice to enable layer-backing explicitly.
    view.wantsLayer = true
    hostingView.wantsLayer = true

    // 将 hostingView 添加到我们的自定义 view 中
    view.addSubview(hostingView)
    view.hostingView = hostingView

    // 设置约束，让 hostingView 填满 CustomZoomableView
    NSLayoutConstraint.activate([
      hostingView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      hostingView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      hostingView.topAnchor.constraint(equalTo: view.topAnchor),
      hostingView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
    ])

    return view
  }

  func updateNSView(_ nsView: CustomZoomableView<Content>, context: Context) {
    // 当 SwiftUI 状态变化时，这里会被调用
    // 我们需要确保 NSHostingView 的 transform 与我们的 state 同步
    let transform = CGAffineTransform.identity
      .translatedBy(x: offset.width, y: offset.height)
      .scaledBy(x: scale, y: scale)

    // FIX 1: Apply the transform to the view's layer, not the view itself.
    nsView.hostingView?.layer?.setAffineTransform(transform)
  }

  func makeCoordinator() -> Coordinator {
    // 创建 Coordinator 实例
    Coordinator(self)
  }

  // MARK: - Coordinator

  class Coordinator: NSObject {
    var parent: ZoomableContainerView

    init(_ parent: ZoomableContainerView) {
      self.parent = parent
    }

    // 这个方法会被 CustomZoomableView 调用
    @objc func handleScroll(scale: CGFloat, offset: CGSize) {
      // 更新绑定到父 SwiftUI 视图的状态
      parent.scale = scale
      parent.offset = offset
    }
  }
}

// MARK: - Custom NSView

class CustomZoomableView<Content: View>: NSView {
  // FIX 2: The coordinator reference now correctly uses the generic parameter.
  weak var coordinator: ZoomableContainerView<Content>.Coordinator?
  // CHANGED: The hostingView reference is now also strongly typed.
  weak var hostingView: NSHostingView<Content>?

  // 我们需要重写这个方法来告诉系统我们的 view 可以成为第一响应者，从而接收键盘和鼠标事件
  override var acceptsFirstResponder: Bool { true }

  // 当滚轮事件发生时，这个方法会被系统调用
  override func scrollWheel(with event: NSEvent) {
    // 检查是否按下了 Control 键
    // 你可以改成 .command, .option, .shift 等
    if event.modifierFlags.contains(.control) {
      guard let currentScale = coordinator?.parent.scale,
        let currentOffset = coordinator?.parent.offset
      else {
        return
      }

      // --- 核心缩放逻辑 ---
      let zoomSensitivity: CGFloat = 0.1
      let minScale: CGFloat = 0.5
      let maxScale: CGFloat = 10.0

      let delta = event.scrollingDeltaY
      var newScale = currentScale + delta * zoomSensitivity
      newScale = max(minScale, min(newScale, maxScale))

      let mouseLocation = self.convert(event.locationInWindow, from: nil)

      let pointInContent = CGPoint(
        x: (mouseLocation.x - currentOffset.width) / currentScale,
        y: (mouseLocation.y - currentOffset.height) / currentScale
      )

      let newPointInScaledContent = CGPoint(
        x: pointInContent.x * newScale,
        y: pointInContent.y * newScale
      )

      let newOffset = CGSize(
        width: mouseLocation.x - newPointInScaledContent.x,
        height: mouseLocation.y - newPointInScaledContent.y
      )

      coordinator?.handleScroll(scale: newScale, offset: newOffset)

    } else if event.modifierFlags.isEmpty {
      guard let currentScale = coordinator?.parent.scale,
        let currentOffset = coordinator?.parent.offset
      else { return }

      let newOffset = CGSize(
        width: currentOffset.width + event.scrollingDeltaX,
        height: currentOffset.height + event.scrollingDeltaY
      )

      coordinator?.handleScroll(scale: currentScale, offset: newOffset)
    } else {
      // 如果按下了其他功能键，或者不希望处理，可以调用 super
      super.scrollWheel(with: event)
    }
  }

  // 如果需要，也可以在这里实现拖动手势
  override func mouseDragged(with event: NSEvent) {
    // 可以实现鼠标左键拖动
  }
}
