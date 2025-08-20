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

    if let imageView = nsView.documentView as? NSImageView, imageView.image != image {
      nsView.setImage(image)
    }
  }
}

// MARK: - Core AppKit Component: The Custom ScrollView
class ZoomableScrollView: NSScrollView {

  var appSettings: AppSettings?
  private let centeringClipView = CenteringClipView()
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
    contentView = centeringClipView
    documentView = imageView
    imageView.translatesAutoresizingMaskIntoConstraints = true

    // --- 关键修复：恢复滚动条机制，但使其自动隐藏 ---
    hasVerticalScroller = true
    hasHorizontalScroller = true
    scrollerStyle = .overlay  // 滚动条只在滚动时浮现，平时隐藏
    // ------------------------------------------

    // --- 标准配置 ---
    drawsBackground = true
    backgroundColor = .windowBackgroundColor
    allowsMagnification = true
    minMagnification = 0.1
    maxMagnification = 10.0
  }

  /// 统一的入口方法：设置或更新显示的图片，并重置视图状态
  func setImage(_ image: NSImage) {
    imageView.image = image
    imageView.frame.size = image.size
    magnification = 1.0
    contentView.scroll(to: .zero)
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

    magnification = min(scaleX, scaleY)
  }

  /// 监听窗口大小变化
  override func setFrameSize(_ newSize: NSSize) {
    let oldSize = frame.size
    super.setFrameSize(newSize)
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

      let pointInView = convert(event.locationInWindow, from: nil)
      let pointInDoc = convert(pointInView, to: documentView)

      setMagnification(newMagnification, centeredAt: pointInDoc)
    } else {
      // 当没有按下修饰键时，允许正常的滚轮滚动
      super.scrollWheel(with: event)
    }
  }

  // --- 已完善的拖动逻辑 ---
  override func mouseDown(with event: NSEvent) {
    guard let settings = appSettings, let documentView = self.documentView else {
      super.mouseDown(with: event)
      return
    }

    // 首要条件：内容是否大于预览区？
    let contentIsLargerThanBounds =
      documentView.frame.width > bounds.width || documentView.frame.height > bounds.height

    // 只有在内容大于预览区时，才检查拖动快捷键
    if contentIsLargerThanBounds {
      // isModifierKeyPressed 会正确处理 .none 的情况（要求没有修饰键按下）
      // 和其他修饰键（要求对应修饰键被按下）
      if settings.isModifierKeyPressed(event.modifierFlags, for: settings.panModifierKey) {
        // 条件满足，允许拖动
        super.mouseDown(with: event)
      }
    }
  }
}

// MARK: - The Key to Centering: The Custom NSClipView
class CenteringClipView: NSClipView {
  override func constrainBoundsRect(_ proposedBounds: NSRect) -> NSRect {
    var rect = super.constrainBoundsRect(proposedBounds)
    guard let documentView = self.documentView else { return rect }

    if rect.size.width > documentView.frame.size.width {
      rect.origin.x = (documentView.frame.width - rect.width) / 2
    }

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
