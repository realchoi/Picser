//
//  ZoomableImageView.swift
//  PicTube
//
//  Created by Eric Cai on 2025/8/21.
//

import AppKit
import SwiftUI

/// 纯SwiftUI实现的缩放图片视图
struct ZoomableImageView: View {
  let image: NSImage

  @EnvironmentObject var appSettings: AppSettings

  // MARK: - 缩放状态管理
  @State private var scale: CGFloat = 1.0
  @State private var lastScale: CGFloat = 1.0
  @State private var minScale: CGFloat = 0.1
  @State private var maxScale: CGFloat = 10.0

  // MARK: - 拖拽状态管理
  @State private var offset: CGSize = .zero
  @State private var lastOffset: CGSize = .zero
  @State private var isDragging: Bool = false

  // MARK: - 手势状态
  @GestureState private var magnificationState: CGFloat = 1.0
  @GestureState private var dragState: CGSize = .zero

  // MARK: - 计算属性
  // 基础适配缩放比例（使图片恰好"适配"预览区域），实际显示尺寸 = 原始尺寸 * baseFitScale * scale
  @State private var baseFitScale: CGFloat = 1.0

  // MARK: - 轻量级缓存（仅用于滚轮缩放优化）
  @State private var cachedMaxOffset: CGSize?
  @State private var cachedScale: CGFloat = 1.0

  private var effectiveScale: CGFloat {
    scale
  }

  private var effectiveOffset: CGSize {
    offset
  }

  var body: some View {
    GeometryReader { geometry in
      ZStack {
        // 图片内容
        AnimatableImageView(image: image)
          //.resizable()
          //.aspectRatio(contentMode: .fit)
          .frame(maxWidth: .infinity, maxHeight: .infinity)
          .scaleEffect(effectiveScale)
          .offset(effectiveOffset)
          // 使用overlay添加滚轮处理
          .overlay(
            ScrollWheelHandler { deltaY in
              // 检查是否应该响应滚轮缩放（修饰键检测）
              guard shouldRespondToZoomGesture() else { return }

              // 处理滚轮缩放
              let zoomFactor = 1.0 + (deltaY * appSettings.zoomSensitivity)
              let newScale = scale * zoomFactor
              let clampedScale = max(minScale, min(maxScale, newScale))

              withAnimation(.easeInOut(duration: 0.1)) {
                scale = clampedScale
                lastScale = clampedScale
                // 缩放后约束偏移量，防止越界
                // 使用缓存的 maxOffset 避免重复计算
                let maxOffset = getCachedMaxOffset(geometry: geometry)
                offset = clamp(offset, to: maxOffset)
                lastOffset = clamp(lastOffset, to: maxOffset)
                // 缓存计算结果，避免下次滚轮缩放时重复计算
                cacheMaxOffset(maxOffset, for: clampedScale)
              }
            }
          )
          .gesture(
            // 拖拽手势
            DragGesture()
              .onChanged { value in
                // 检查是否应该响应拖拽（修饰键检测）
                guard shouldRespondToPanGesture() else { return }
                // 仅当图片超过预览区域边界时允许拖拽
                let maxOffset = calculateMaxOffset(geometry: geometry)
                let canPanNow = (maxOffset.width > 0.0) || (maxOffset.height > 0.0)
                guard canPanNow else { return }

                if !isDragging {
                  isDragging = true
                  NSCursor.closedHand.set()
                }

                let proposed = CGSize(
                  width: lastOffset.width + value.translation.width,
                  height: lastOffset.height + value.translation.height
                )
                offset = clamp(proposed, to: maxOffset)
              }
              .onEnded { value in
                // 检查是否应该响应拖拽（修饰键检测）
                guard shouldRespondToPanGesture() else { return }
                let maxOffset = calculateMaxOffset(geometry: geometry)
                let proposed = CGSize(
                  width: lastOffset.width + value.translation.width,
                  height: lastOffset.height + value.translation.height
                )
                let clamped = clamp(proposed, to: maxOffset)
                withAnimation(.easeInOut(duration: 0.2)) {
                  offset = clamped
                }
                lastOffset = clamped
                isDragging = false
                NSCursor.arrow.set()
              }
          )
          .onTapGesture(count: 2) {
            // 双击重置缩放
            resetZoom()
          }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .onAppear {
        setupInitialState(geometry: geometry)
      }
    }
    .onChange(of: appSettings.minZoomScale) { _, newValue in
      minScale = newValue
      ensureValidScale()
      invalidateCache()  // 缩放限制变化时清除缓存
    }
    .onChange(of: appSettings.maxZoomScale) { _, newValue in
      maxScale = newValue
      ensureValidScale()
      invalidateCache()  // 缩放限制变化时清除缓存
    }
    .onChange(of: image) { _, _ in
      // 图片变化时重置拖拽状态（缩放重置在GeometryReader内部处理）
      resetPan()
      invalidateCache()  // 图片变化时清除缓存
    }
    .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResizeNotification)) { _ in
      // 窗口大小变化时重新适应 - 需要在GeometryReader内部处理
      invalidateCache()  // 窗口大小变化时清除缓存
    }
  }

  // MARK: - 私有方法

  /// 检查是否应该响应缩放手势（修饰键检测）
  private func shouldRespondToZoomGesture() -> Bool {
    // 如果修饰键设置为none，始终允许手势
    if appSettings.zoomModifierKey == .none {
      return true
    }

    // 否则检查是否按下了指定的修饰键
    guard let event = NSApplication.shared.currentEvent else { return false }
    return appSettings.isModifierKeyPressed(event.modifierFlags, for: appSettings.zoomModifierKey)
  }

  /// 检查是否应该响应拖拽手势（修饰键检测）
  private func shouldRespondToPanGesture() -> Bool {
    // 如果修饰键设置为none，始终允许拖拽
    if appSettings.panModifierKey == .none {
      return true
    }

    // 否则检查是否按下了指定的修饰键
    guard let event = NSApplication.shared.currentEvent else { return false }
    return appSettings.isModifierKeyPressed(event.modifierFlags, for: appSettings.panModifierKey)
  }

  /// 设置初始状态
  private func setupInitialState(geometry: GeometryProxy) {
    minScale = appSettings.minZoomScale
    maxScale = appSettings.maxZoomScale
    // 延迟一帧确保视图完全布局
    DispatchQueue.main.async {
      fitImageToView(geometry: geometry)
    }
  }

  /// 计算最大拖拽偏移量
  private func calculateMaxOffset(geometry: GeometryProxy) -> CGSize {
    // 根据当前缩放比例和实际视图尺寸计算最大拖拽范围
    let viewSize = geometry.size
    let imageSize = image.size

    // 使用显示尺寸参与边界计算：原始尺寸 * baseFitScale(适配) * scale(相对缩放)
    let displayedWidth = imageSize.width * baseFitScale * scale
    let displayedHeight = imageSize.height * baseFitScale * scale
    let maxOffsetX = max(0, (displayedWidth - viewSize.width) / 2)
    let maxOffsetY = max(0, (displayedHeight - viewSize.height) / 2)

    return CGSize(width: maxOffsetX, height: maxOffsetY)
  }

  /// 将给定偏移量限制在最大边界内
  private func clamp(_ value: CGSize, to maxOffset: CGSize) -> CGSize {
    CGSize(
      width: max(-maxOffset.width, min(maxOffset.width, value.width)),
      height: max(-maxOffset.height, min(maxOffset.height, value.height))
    )
  }

  /// 确保缩放比例在有效范围内
  private func ensureValidScale() {
    if scale < minScale {
      scale = minScale
    } else if scale > maxScale {
      scale = maxScale
    }
  }

  /// 重置缩放
  private func resetZoom() {
    withAnimation(.easeInOut(duration: 0.3)) {
      scale = 1.0
      lastScale = 1.0
      // 重置缩放时也要重置偏移量，确保图片在视野范围内
      offset = .zero
      lastOffset = .zero
      // 清除缓存，因为缩放比例已改变
      invalidateCache()
    }
  }

  /// 重置拖拽
  private func resetPan() {
    withAnimation(.easeInOut(duration: 0.3)) {
      offset = .zero
      lastOffset = .zero
    }
  }

  /// 适应窗口大小：记录基础适配比例，并将相对缩放恢复为1（即刚好适配）
  private func fitImageToView(geometry: GeometryProxy) {
    let viewSize = geometry.size
    let imageSize = image.size

    guard imageSize.width > 0, imageSize.height > 0, viewSize.width > 0, viewSize.height > 0 else {
      scale = 1.0
      lastScale = 1.0
      return
    }

    let scaleX = viewSize.width / imageSize.width
    let scaleY = viewSize.height / imageSize.height

    let fitScale = min(scaleX, scaleY)
    baseFitScale = fitScale

    withAnimation(.easeInOut(duration: 0.25)) {
      // 相对缩放设置为1.0（表示在基础适配尺寸上不额外缩放）
      scale = 1.0
      lastScale = 1.0
      offset = .zero
      lastOffset = .zero
      // 基础适配比例变化时清除缓存
      invalidateCache()
    }
  }

  /// 缓存最大偏移量
  private func cacheMaxOffset(_ maxOffset: CGSize, for scale: CGFloat) {
    cachedMaxOffset = maxOffset
    cachedScale = scale
  }

  /// 获取缓存的缩放比例
  private func getCachedScale() -> CGFloat {
    cachedScale
  }

  /// 获取缓存的缩放比例对应的偏移量
  private func getCachedMaxOffset(geometry: GeometryProxy) -> CGSize {
    // 检查缓存是否有效（缩放比例是否匹配）
    if let cached = cachedMaxOffset, abs(cachedScale - scale) < 0.001 {
      return cached
    }

    // 缓存无效，重新计算
    let maxOffset = calculateMaxOffset(geometry: geometry)
    return maxOffset
  }

  /// 清除缓存（在需要时调用）
  private func invalidateCache() {
    cachedMaxOffset = nil
  }
}

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

/// 使用 NSViewRepresentable 封装 NSImageView，以支持 GIF 动画播放
struct AnimatableImageView: NSViewRepresentable {
  let image: NSImage

  func makeNSView(context: Context) -> NSImageView {
    let imageView = NSImageView()
    imageView.image = image
    imageView.imageScaling = .scaleProportionallyUpOrDown
    imageView.animates = true  // 关键：允许播放动画
    imageView.isEditable = false
    imageView.setContentCompressionResistancePriority(.fittingSizeCompression, for: .horizontal)
    imageView.setContentCompressionResistancePriority(.fittingSizeCompression, for: .vertical)
    return imageView
  }

  func updateNSView(_ nsView: NSImageView, context: Context) {
    nsView.image = image
  }
}

#Preview {
  if let testImage = NSImage(systemSymbolName: "photo", accessibilityDescription: nil) {
    ZoomableImageView(image: testImage)
      .environmentObject(AppSettings())
      .frame(width: 400, height: 300)
  } else {
    Text("无法加载测试图片")
  }
}
