//
//  NativeZoomableImageView.swift
//  PicTube
//
//  Created by Eric Cai on 2025/8/20.
//

import AppKit
import SwiftUI

struct NativeZoomableImageView: NSViewRepresentable {
  let image: NSImage

  // 接收设置对象
  @EnvironmentObject var appSettings: AppSettings

  // MARK: - 辅助方法

  // 计算图片适配容器的尺寸 (aspectRatio(.fit) 逻辑)
  private func calculateFittedSize(imageSize: CGSize, containerSize: CGSize) -> CGSize {
    guard
      imageSize.width > 0 && imageSize.height > 0 && containerSize.width > 0
        && containerSize.height > 0
    else {
      return imageSize
    }

    let imageAspect = imageSize.width / imageSize.height
    let containerAspect = containerSize.width / containerSize.height

    if imageAspect > containerAspect {
      // 图片更宽，以容器宽度为准
      let fittedWidth = containerSize.width
      let fittedHeight = fittedWidth / imageAspect
      return CGSize(width: fittedWidth, height: fittedHeight)
    } else {
      // 图片更高，以容器高度为准
      let fittedHeight = containerSize.height
      let fittedWidth = fittedHeight * imageAspect
      return CGSize(width: fittedWidth, height: fittedHeight)
    }
  }

  func makeNSView(context: Context) -> CustomScrollView {
    let scrollView = CustomScrollView()
    let imageView = NSImageView()

    // 配置 NSScrollView 的缩放功能
    scrollView.allowsMagnification = true
    scrollView.minMagnification = 0.1
    scrollView.maxMagnification = 10.0
    scrollView.magnification = 1.0

    // 配置滚动条
    scrollView.hasVerticalScroller = true
    scrollView.hasHorizontalScroller = true
    scrollView.autohidesScrollers = true
    scrollView.scrollerStyle = .overlay

    // 配置其他属性
    scrollView.backgroundColor = NSColor.windowBackgroundColor
    scrollView.drawsBackground = true

    // 设置应用设置
    scrollView.appSettings = appSettings

    // 配置 NSImageView - 使用原生居中和适配
    imageView.image = image
    imageView.imageScaling = .scaleProportionallyUpOrDown
    imageView.imageAlignment = .alignCenter

    // 设置 imageView 的 frame 为容器尺寸，让其内部处理居中
    imageView.frame = CGRect(origin: .zero, size: CGSize(width: 800, height: 600))  // 临时尺寸，会在 layout 中更新

    // 存储图片引用到 scrollView，供后续布局使用
    scrollView.currentImage = image

    // 将 imageView 设置为 scrollView 的 documentView
    scrollView.documentView = imageView

    return scrollView
  }

  func updateNSView(_ nsView: CustomScrollView, context: Context) {
    // 更新应用设置
    nsView.appSettings = appSettings

    // 当图片改变时更新 imageView
    if let imageView = nsView.documentView as? NSImageView {
      // 检查是否是新图片
      if imageView.image != image {
        imageView.image = image
        nsView.currentImage = image

        // 重置布局标志和尺寸记录，让新图片重新计算适配尺寸
        nsView.hasPerformedInitialLayout = false
        nsView.lastContainerSize = .zero

        // 如果容器已有合理尺寸，设置 imageView frame 为容器尺寸
        if nsView.bounds.size.width > 0 && nsView.bounds.size.height > 0 {
          imageView.frame = nsView.bounds
          nsView.hasPerformedInitialLayout = true
          nsView.lastContainerSize = nsView.bounds.size
        }

        // 重置缩放比例
        nsView.magnification = 1.0
      }
    }
  }

  func makeCoordinator() -> Coordinator {
    Coordinator(self)
  }

  // MARK: - Coordinator

  class Coordinator: NSObject {
    var parent: NativeZoomableImageView

    init(_ parent: NativeZoomableImageView) {
      self.parent = parent
    }
  }
}

// MARK: - Custom NSScrollView

class CustomScrollView: NSScrollView {
  var appSettings: AppSettings?
  var currentImage: NSImage?
  var hasPerformedInitialLayout = false
  var lastContainerSize: CGSize = .zero

  override var acceptsFirstResponder: Bool { true }

  // 在视图布局完成后设置 documentView 尺寸
  override func layout() {
    super.layout()

    let currentSize = bounds.size

    // 检查容器尺寸是否发生了变化，或者是否是首次布局
    let isFirstLayout = !hasPerformedInitialLayout
    let sizeChanged =
      abs(currentSize.width - lastContainerSize.width) > 1
      || abs(currentSize.height - lastContainerSize.height) > 1

    if isFirstLayout || sizeChanged {
      // --- 问题修复开始 ---

      // 修复问题2: 当窗口大小变化时，重置缩放比例。
      // 这会使图片以原始的 "fit" 模式重新适应并填充新的预览区。
      self.magnification = 1.0

      if let imageView = documentView as? NSImageView {
        // 重新设置 imageView 的 frame 等同于预览区的大小。
        // 结合 NSImageView 的 .alignCenter 属性，可以确保图片内容始终居中。
        // 这个操作同时解决了问题1，因为当缩放比例重置为1.0时，图片会自然居中。
        imageView.frame = bounds
      }

      // 更新布局状态
      hasPerformedInitialLayout = true
      lastContainerSize = currentSize
      // --- 问题修复结束 ---
    }
  }

  // 处理滚轮事件 - 实现缩放功能
  override func scrollWheel(with event: NSEvent) {
    guard let settings = appSettings else {
      super.scrollWheel(with: event)
      return
    }

    // 检查是否按下了缩放修饰键
    if settings.isModifierKeyPressed(event.modifierFlags, for: settings.zoomModifierKey) {
      // 使用原生缩放功能
      let zoomSensitivity = settings.zoomSensitivity
      let minMagnification = settings.minZoomScale
      let maxMagnification = settings.maxZoomScale

      let delta = event.scrollingDeltaY
      var newMagnification = self.magnification + delta * zoomSensitivity
      newMagnification = max(minMagnification, min(newMagnification, maxMagnification))

      // 使用容器中心点进行缩放
      let containerCenter = CGPoint(x: bounds.width / 2, y: bounds.height / 2)
      self.setMagnification(newMagnification, centeredAt: containerCenter)
    } else {
      // 如果没有按下缩放修饰键，调用默认滚动行为
      super.scrollWheel(with: event)
    }
  }

  // 处理鼠标拖动 - 实现拖动功能
  override func mouseDown(with event: NSEvent) {
    guard let settings = appSettings else {
      super.mouseDown(with: event)
      return
    }

    // 检查修饰键状态，决定是否开始拖动
    let shouldStartDrag =
      settings.isModifierKeyPressed(
        event.modifierFlags, for: settings.panModifierKey)
      // 如果图片被放大了，也允许拖动
      || self.magnification > 1.0

    if shouldStartDrag {
      // 启用拖动模式
      super.mouseDown(with: event)
    } else {
      super.mouseDown(with: event)
    }
  }
}

#Preview {
  if let testImage = NSImage(systemSymbolName: "photo", accessibilityDescription: nil) {
    NativeZoomableImageView(image: testImage)
      .frame(width: 400, height: 300)
  } else {
    Text("无法加载测试图片")
  }
}
