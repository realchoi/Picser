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
  let originalImageSize: CGSize  // 图片的原始尺寸

  // 接收设置对象
  @EnvironmentObject var appSettings: AppSettings

  // 添加 @ViewBuilder 初始化器
  init(
    scale: Binding<CGFloat>, offset: Binding<CGSize>, originalImageSize: CGSize,
    @ViewBuilder content: () -> Content
  ) {
    self._scale = scale
    self._offset = offset
    self.originalImageSize = originalImageSize
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
    // 传递图片原始尺寸到 NSView
    view.originalImageSize = originalImageSize

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
    // 更新图片原始尺寸
    nsView.originalImageSize = originalImageSize
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
  // 图片原始尺寸
  var originalImageSize: CGSize = .zero

  // 拖动状态管理
  private var isDragging = false
  private var dragStartPoint: CGPoint = .zero
  private var dragStartOffset: CGSize = .zero

  // 我们需要重写这个方法来告诉系统我们的 view 可以成为第一响应者，从而接收键盘和鼠标事件
  override var acceptsFirstResponder: Bool { true }

  // MARK: - 辅助方法

  // 获取当前图片的实际尺寸
  private func getImageSize() -> CGSize? {
    guard let hostingView = hostingView else { return nil }

    // 获取 hostingView 的内在内容尺寸
    let intrinsicSize = hostingView.intrinsicContentSize

    // 如果内在尺寸无效，尝试获取 fittingSize
    if intrinsicSize.width == NSView.noIntrinsicMetric
      || intrinsicSize.height == NSView.noIntrinsicMetric
    {
      return hostingView.fittingSize
    }

    return intrinsicSize
  }

  // 判断是否应该启用拖动功能
  private func shouldEnablePanning() -> Bool {
    guard let currentScale = coordinator?.parent.scale else {
      return false
    }

    // 计算图片在 aspectRatio(.fit) 模式下的实际渲染尺寸
    let fittedImageSize = calculateFittedImageSize()

    // 如果计算失败，返回 false
    guard fittedImageSize.width > 0 && fittedImageSize.height > 0 else {
      return false
    }

    // 计算图片在当前缩放下的最终显示尺寸
    let scaledImageSize = CGSize(
      width: fittedImageSize.width * currentScale,
      height: fittedImageSize.height * currentScale
    )

    // 获取容器尺寸
    let containerSize = self.bounds.size

    // 如果图片任一维度超出容器，则启用拖动
    return scaledImageSize.width > containerSize.width
      || scaledImageSize.height > containerSize.height
  }

  // 获取容器中心点坐标
  private func getContainerCenter() -> CGPoint {
    let containerSize = self.bounds.size
    return CGPoint(
      x: containerSize.width / 2,
      y: containerSize.height / 2
    )
  }

  // 计算 aspectRatio(.fit) 模式下的实际渲染尺寸
  private func calculateFittedImageSize() -> CGSize {
    let containerSize = self.bounds.size

    // 如果容器尺寸为零或图片尺寸为零，返回零尺寸
    guard
      containerSize.width > 0 && containerSize.height > 0 && originalImageSize.width > 0
        && originalImageSize.height > 0
    else {
      return .zero
    }

    // 计算图片和容器的宽高比
    let imageAspectRatio = originalImageSize.width / originalImageSize.height
    let containerAspectRatio = containerSize.width / containerSize.height

    // 根据 aspectRatio(.fit) 的逻辑计算适配后的尺寸
    if imageAspectRatio > containerAspectRatio {
      // 图片更宽，以容器宽度为准
      let fittedWidth = containerSize.width
      let fittedHeight = fittedWidth / imageAspectRatio
      return CGSize(width: fittedWidth, height: fittedHeight)
    } else {
      // 图片更高，以容器高度为准
      let fittedHeight = containerSize.height
      let fittedWidth = fittedHeight * imageAspectRatio
      return CGSize(width: fittedWidth, height: fittedHeight)
    }
  }

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

      // 使用容器中心作为缩放点，而不是鼠标位置
      let containerCenter = getContainerCenter()

      // 计算缩放比例变化
      let scaleRatio = newScale / currentScale

      // 计算新的偏移量，确保图片相对于容器中心进行缩放
      let newOffset = CGSize(
        width: containerCenter.x + (currentOffset.width - containerCenter.x) * scaleRatio,
        height: containerCenter.y + (currentOffset.height - containerCenter.y) * scaleRatio
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

    // 检查修饰键状态和图片尺寸，决定是否开始拖动
    let modifierKeyPressed = settings.isModifierKeyPressed(
      event.modifierFlags, for: settings.panModifierKey)

    // 智能拖动启用：当图片超出容器时自动启用，或者按下修饰键时强制启用
    let shouldStartDrag = shouldEnablePanning() || modifierKeyPressed

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
    // 确保拖动状态已启用
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
