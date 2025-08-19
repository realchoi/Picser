//
//  ZoomableContainerView.swift
//  PicTube
//
//  Created by Eric Cai on 2025/8/19.
//

import AppKit
import Foundation
import SwiftUI

struct ZoomableContainerView<Content: View>: NSViewRepresentable {
  // 通过 Binding 从父视图接收 scale 和 offset
  @Binding var scale: CGFloat
  @Binding var offset: CGSize
  let content: Content  // 要被包裹和缩放的 SwiftUI 视图

  // 接收设置对象
  @EnvironmentObject var appSettings: AppSettings

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
    // 传递设置对象到 NSView
    view.appSettings = appSettings

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

    // 更新设置对象引用
    nsView.appSettings = appSettings
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
  // 设置对象引用
  var appSettings: AppSettings?

  // 拖动状态管理
  private var isDragging = false
  private var dragStartPoint: CGPoint = .zero
  private var dragStartOffset: CGSize = .zero

  // 我们需要重写这个方法来告诉系统我们的 view 可以成为第一响应者，从而接收键盘和鼠标事件
  override var acceptsFirstResponder: Bool { true }

  // 当滚轮事件发生时，这个方法会被系统调用
  override func scrollWheel(with event: NSEvent) {
    guard let settings = appSettings else {
      // 如果没有设置对象，使用默认行为
      super.scrollWheel(with: event)
      return
    }

    // 如果正在进行鼠标拖动，跳过滚轮处理避免冲突
    guard !isDragging else { return }

    // 检查是否按下了缩放修饰键
    if settings.isModifierKeyPressed(event.modifierFlags, for: settings.zoomModifierKey) {
      guard let currentScale = coordinator?.parent.scale,
        let currentOffset = coordinator?.parent.offset
      else {
        return
      }

      // --- 核心缩放逻辑 ---
      let zoomSensitivity: CGFloat = settings.zoomSensitivity
      let minScale: CGFloat = settings.minZoomScale
      let maxScale: CGFloat = settings.maxZoomScale

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
    } else {
      // 如果没有按下缩放修饰键，调用默认行为
      super.scrollWheel(with: event)
    }
  }

  // 鼠标按下事件处理
  override func mouseDown(with event: NSEvent) {
    guard let settings = appSettings else {
      super.mouseDown(with: event)
      return
    }

    // 检查是否为左键点击
    guard event.type == .leftMouseDown else {
      super.mouseDown(with: event)
      return
    }

    // 检查修饰键状态，决定是否开始拖动
    let shouldStartDrag = settings.isModifierKeyPressed(
      event.modifierFlags, for: settings.panModifierKey)

    if shouldStartDrag {
      // 初始化拖动状态
      isDragging = true
      dragStartPoint = self.convert(event.locationInWindow, from: nil)

      // 记录当前偏移量
      if let currentOffset = coordinator?.parent.offset {
        dragStartOffset = currentOffset
      }
    } else {
      super.mouseDown(with: event)
    }
  }

  // 鼠标拖动事件处理
  override func mouseDragged(with event: NSEvent) {
    guard isDragging else {
      super.mouseDragged(with: event)
      return
    }

    guard let currentScale = coordinator?.parent.scale else { return }

    // 计算当前鼠标位置与起始位置的差值
    let currentPoint = self.convert(event.locationInWindow, from: nil)
    let deltaX = currentPoint.x - dragStartPoint.x
    let deltaY = currentPoint.y - dragStartPoint.y

    // 结合起始偏移量计算新的偏移量
    let newOffset = CGSize(
      width: dragStartOffset.width + deltaX,
      height: dragStartOffset.height + deltaY
    )

    // 通过 coordinator 更新 SwiftUI 状态
    coordinator?.handleScroll(scale: currentScale, offset: newOffset)
  }

  // 鼠标释放事件处理
  override func mouseUp(with event: NSEvent) {
    if isDragging {
      // 结束拖动状态
      isDragging = false
      dragStartPoint = .zero
      dragStartOffset = .zero
    } else {
      super.mouseUp(with: event)
    }
  }
}
