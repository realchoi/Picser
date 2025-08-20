//
//  NativeZoomableImageView.swift
//  PicTube
//
//  Created by A Professional Swift Engineer on 2025/8/21.
//

import AppKit
import SwiftUI

// MARK: - SwiftUI View (The Bridge to AppKit)
struct NativeZoomableImageView: NSViewRepresentable {
  let image: NSImage
  @EnvironmentObject var appSettings: AppSettings

  func makeNSView(context: Context) -> ZoomableScrollView {
    let scrollView = ZoomableScrollView()
    scrollView.appSettings = appSettings
    scrollView.setImage(image)
    return scrollView
  }

  func updateNSView(_ nsView: ZoomableScrollView, context: Context) {
    nsView.appSettings = appSettings

    // 修复：正确地将 documentView 转换为 NSImageView
    if let imageView = nsView.documentView as? NSImageView, imageView.image != image {
      nsView.setImage(image)
    }
  }
}

// MARK: - Core AppKit Component: The Custom ScrollView
class ZoomableScrollView: NSScrollView {

  var appSettings: AppSettings?

  // 我们用自定义的 CenteringClipView 替换默认的 clip view
  private let centeringClipView = CenteringClipView()

  // 将 ImageView 声明为类的属性，方便访问
  private let imageView = NSImageView()

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    commonInit()
  }

  required init?(coder: NSCoder) {
    super.init(coder: coder)
    commonInit()
  }

  private func commonInit() {
    // ---- 核心架构设置 ----
    // 1. 替换默认的 contentView 为我们自定义的居中 ClipView
    //    这是实现完美居中的关键，也是最标准、最可靠的方法。
    contentView = centeringClipView

    // 2. 将 imageView 设为 documentView，并确保它的大小可变
    documentView = imageView
    imageView.translatesAutoresizingMaskIntoConstraints = true
    // ----------------------

    // --- 标准配置 ---
    drawsBackground = true
    backgroundColor = .windowBackgroundColor
    allowsMagnification = true
    minMagnification = 0.1
    maxMagnification = 10.0

    hasVerticalScroller = true
    hasHorizontalScroller = true
    scrollerStyle = .overlay
  }

  /// 统一的入口方法：设置或更新显示的图片，并重置视图状态
  func setImage(_ image: NSImage) {
    // 更新图片和尺寸
    imageView.image = image
    imageView.frame.size = image.size

    // 重置缩放和滚动位置，确保新图片从干净的状态开始
    magnification = 1.0
    contentView.scroll(to: .zero)

    // 确保进行初始的 "Fit" 缩放
    fitImageToView()
  }

  /// 计算并应用“适应窗口”的缩放比例
  private func fitImageToView() {
    guard let imageSize = imageView.image?.size, imageSize.width > 0, imageSize.height > 0 else {
      return
    }

    let containerSize = bounds.size
    if containerSize.width == 0 || containerSize.height == 0 { return }

    let scaleX = containerSize.width / imageSize.width
    let scaleY = containerSize.height / imageSize.height

    // 取较小的缩放比例以确保整个图片都可见
    magnification = min(scaleX, scaleY)
  }

  /// 监听窗口大小变化
  override func setFrameSize(_ newSize: NSSize) {
    let oldSize = frame.size
    super.setFrameSize(newSize)

    // 仅当尺寸确实发生变化时才重新适应图片
    if !CGSizeEqualToSize(oldSize, newSize) {
      fitImageToView()
    }
  }

  // 处理滚轮事件
  override func scrollWheel(with event: NSEvent) {
    guard let settings = appSettings else {
      super.scrollWheel(with: event)
      return
    }

    if settings.isModifierKeyPressed(event.modifierFlags, for: settings.zoomModifierKey) {
      let zoomSensitivity = settings.zoomSensitivity
      let minMagnification = settings.minZoomScale
      let maxMagnification = settings.maxZoomScale
      let delta = event.scrollingDeltaY
      var newMagnification = magnification + delta * zoomSensitivity
      newMagnification = max(minMagnification, min(newMagnification, maxMagnification))

      // 以鼠标指针的位置为中心进行缩放，提供最自然的用户体验
      let pointInView = convert(event.locationInWindow, from: nil)
      let pointInDoc = convert(pointInView, to: documentView)

      setMagnification(newMagnification, centeredAt: pointInDoc)
    } else {
      // 允许在没有修饰键时进行正常的滚动
      super.scrollWheel(with: event)
    }
  }
}

// MARK: - The Key to Centering: The Custom NSClipView
/// 一个自定义的 NSClipView，它会始终将其内部的 documentView 居中。
/// 这是解决 NSScrollView 内容小于视图时居中问题的标准、可靠方法。
class CenteringClipView: NSClipView {
  override func constrainBoundsRect(_ proposedBounds: NSRect) -> NSRect {
    var rect = super.constrainBoundsRect(proposedBounds)
    guard let documentView = self.documentView else { return rect }

    // 如果内容的宽度小于视图宽度，调整 x 坐标以实现水平居中
    if rect.size.width > documentView.frame.size.width {
      rect.origin.x = (documentView.frame.width - rect.width) / 2
    }

    // 如果内容的高度小于视图高度，调整 y 坐标以实现垂直居中
    if rect.size.height > documentView.frame.size.height {
      rect.origin.y = (documentView.frame.height - rect.height) / 2
    }

    return rect
  }
}

#Preview {
  if let testImage = NSImage(systemSymbolName: "photo", accessibilityDescription: nil) {
    NativeZoomableImageView(image: testImage)
      .environmentObject(AppSettings())
      .frame(width: 400, height: 300)
  } else {
    Text("无法加载测试图片")
  }
}
