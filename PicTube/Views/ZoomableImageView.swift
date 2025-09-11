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

  // MARK: - 小地图显示控制（自动隐藏）
  @State private var minimapUserVisible: Bool = true
  @State private var minimapHideTask: Task<Void, Never>?

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
              // 交互后触发小地图显示并启动自动隐藏计时
              triggerMinimapAutoHide()
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
                // 拖拽过程中刷新小地图可见性
                triggerMinimapAutoHide()
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
                // 拖拽结束后继续计时隐藏
                triggerMinimapAutoHide()
              }
          )
          // 触控板捏合缩放手势（与滚轮缩放共存）
          .simultaneousGesture(
            MagnificationGesture()
              .onChanged { value in
                // 与滚轮缩放一样，遵从修饰键设置
                guard shouldRespondToZoomGesture() else { return }
                // value 是相对比例（1.0 为不变）
                let proposed = lastScale * value
                let clamped = max(minScale, min(maxScale, proposed))
                withAnimation(.easeInOut(duration: 0.08)) {
                  scale = clamped
                  // 缩放后更新并夹取偏移，避免越界
                  let maxOffset = calculateMaxOffset(geometry: geometry)
                  offset = clamp(offset, to: maxOffset)
                }
                // 捏合过程中刷新小地图可见性
                triggerMinimapAutoHide()
              }
              .onEnded { value in
                // 结束时固化缩放比例，并同步偏移缓存
                let proposed = lastScale * value
                let clamped = max(minScale, min(maxScale, proposed))
                lastScale = clamped
                let maxOffset = calculateMaxOffset(geometry: geometry)
                lastOffset = clamp(offset, to: maxOffset)
                // 清理滚轮缓存，使后续滚轮缩放重新计算边界
                invalidateCache()
                // 捏合结束后继续计时隐藏
                triggerMinimapAutoHide()
              }
          )
          .onTapGesture(count: 2) {
            // 双击重置缩放
            resetZoom()
          }
      }
      // 小地图（缩略图）覆盖层：当图片放大超过预览区域且设置允许时显示
      .overlay(alignment: .bottomTrailing) {
        if shouldShowMinimap(geometry: geometry)
          && appSettings.showMinimap
          && (appSettings.minimapAutoHideSeconds <= 0 || minimapUserVisible)
        {
          let visRect = currentVisibleRectInImage(geometry: geometry)
          MinimapOverlay(
            image: image,
            containerSize: CGSize(width: 180, height: 140),
            visibleRectInImage: visRect
          )
          .padding(10)
          .transition(.opacity.combined(with: .move(edge: .bottom)))
          .animation(.easeInOut(duration: 0.15), value: visRect)
          .allowsHitTesting(false)
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .onAppear {
        setupInitialState(geometry: geometry)
        // 初始可见性：若开启自动隐藏，则等待用户交互再显示
        minimapUserVisible = appSettings.minimapAutoHideSeconds <= 0
      }
      .onChange(of: image) { _, _ in
        // 图片切换时，重新按视口适配并重置缩放/偏移，避免使用上一张图的 baseFitScale
        fitImageToView(geometry: geometry)
        minimapUserVisible = appSettings.minimapAutoHideSeconds <= 0
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
    // 图片变化时的重置逻辑已在 GeometryReader 内部的 onChange 处理
    .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResizeNotification)) { _ in
      // 窗口大小变化时重新适应 - 需要在GeometryReader内部处理
      invalidateCache()  // 窗口大小变化时清除缓存
    }
    .onDisappear {
      minimapHideTask?.cancel()
      minimapHideTask = nil
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

  /// 是否应显示小地图（当显示尺寸超过视口尺寸时）
  private func shouldShowMinimap(geometry: GeometryProxy) -> Bool {
    let viewSize = geometry.size
    let displayedWidth = image.size.width * baseFitScale * scale
    let displayedHeight = image.size.height * baseFitScale * scale
    return displayedWidth > viewSize.width + 0.5 || displayedHeight > viewSize.height + 0.5
  }

  /// 计算当前视口在原始图像坐标系（以像素为单位）中的可见矩形
  private func currentVisibleRectInImage(geometry: GeometryProxy) -> CGRect {
    let vw = geometry.size.width
    let vh = geometry.size.height
    let iw = image.size.width
    let ih = image.size.height

    guard iw > 0, ih > 0, vw > 0, vh > 0 else { return .zero }

    let sDisp = baseFitScale * scale

    // 将视图矩形 [0,vw]x[0,vh] 映射回图像坐标
    // 推导：imageX = (viewX - vw/2 - offsetX)/sDisp + iw/2
    //       imageY = (viewY - vh/2 - offsetY)/sDisp + ih/2
    let imgLeft = (-vw / 2.0 - offset.width) / sDisp + iw / 2.0
    let imgRight = (vw / 2.0 - offset.width) / sDisp + iw / 2.0
    let imgTop = (-vh / 2.0 - offset.height) / sDisp + ih / 2.0
    let imgBottom = (vh / 2.0 - offset.height) / sDisp + ih / 2.0

    // 与原图边界相交
    let x0 = max(0.0, min(iw, imgLeft))
    let x1 = max(0.0, min(iw, imgRight))
    let y0 = max(0.0, min(ih, imgTop))
    let y1 = max(0.0, min(ih, imgBottom))

    let width = max(0.0, x1 - x0)
    let height = max(0.0, y1 - y0)
    return CGRect(x: x0, y: y0, width: width, height: height)
  }

  /// 触发小地图显示并按设置自动隐藏
  private func triggerMinimapAutoHide() {
    guard appSettings.showMinimap else { return }
    minimapUserVisible = true
    minimapHideTask?.cancel()
    let delay = appSettings.minimapAutoHideSeconds
    guard delay > 0 else { return }
    let task = Task { @MainActor in
      try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
      if !Task.isCancelled {
        minimapUserVisible = false
      }
    }
    minimapHideTask = task
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

// MARK: - Minimap Overlay
/// 右下角的小地图缩略视图，展示原图及当前视口位置
private struct MinimapOverlay: View {
  let image: NSImage
  let containerSize: CGSize
  let visibleRectInImage: CGRect // 在原图坐标中的可见区域

  // 外观参数
  private let cornerRadius: CGFloat = 8
  private let borderColor: Color = Color.white.opacity(0.9)
  private let borderWidth: CGFloat = 1
  private let backdropColor: Color = Color.black.opacity(0.25)
  private let contentPadding: CGFloat = 6
  private let viewportStrokeColor: Color = .accentColor
  private let viewportFillColor: Color = Color.accentColor.opacity(0.12)

  var body: some View {
    ZStack(alignment: .topLeading) {
      // 背景（半透明毛玻璃风格）
      RoundedRectangle(cornerRadius: cornerRadius)
        .fill(backdropColor)
        .overlay(
          RoundedRectangle(cornerRadius: cornerRadius)
            .stroke(borderColor, lineWidth: 0.5)
        )

      // 内容层：原图缩略 + 视口框
      MinimapContent(
        image: image,
        containerSize: containerSize,
        contentPadding: contentPadding,
        visibleRectInImage: visibleRectInImage,
        viewportStrokeColor: viewportStrokeColor,
        viewportFillColor: viewportFillColor,
        borderWidth: borderWidth
      )
      .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
    }
    .frame(width: containerSize.width, height: containerSize.height)
    .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 2)
  }
}

/// 小地图主体内容：计算缩略图适配尺寸并绘制视口矩形
private struct MinimapContent: View {
  let image: NSImage
  let containerSize: CGSize
  let contentPadding: CGFloat
  let visibleRectInImage: CGRect
  let viewportStrokeColor: Color
  let viewportFillColor: Color
  let borderWidth: CGFloat

  var body: some View {
    // 计算缩略图适配结果
    let iw = max(1.0, image.size.width)
    let ih = max(1.0, image.size.height)
    let cw = max(1.0, containerSize.width - contentPadding * 2)
    let ch = max(1.0, containerSize.height - contentPadding * 2)
    let fitScale = min(cw / iw, ch / ih)
    let miniW = iw * fitScale
    let miniH = ih * fitScale
    let ox = (containerSize.width - miniW) / 2.0
    let oy = (containerSize.height - miniH) / 2.0

    // 将可见区域从原图坐标转换到小地图坐标
    let vx = ox + (visibleRectInImage.origin.x / iw) * miniW
    let vy = oy + (visibleRectInImage.origin.y / ih) * miniH
    let vw = (visibleRectInImage.size.width / iw) * miniW
    let vh = (visibleRectInImage.size.height / ih) * miniH

    return ZStack(alignment: .topLeading) {
      // 原图缩略
      Image(nsImage: image)
        .resizable()
        .aspectRatio(contentMode: .fit)
        .frame(width: miniW, height: miniH)
        .position(x: containerSize.width / 2.0, y: containerSize.height / 2.0)

      // 视口矩形
      Rectangle()
        .fill(viewportFillColor)
        .frame(width: max(1, vw), height: max(1, vh))
        .offset(x: vx, y: vy)
        .overlay(
          Rectangle()
            .stroke(viewportStrokeColor, lineWidth: max(1, borderWidth))
            .frame(width: max(1, vw), height: max(1, vh))
            .offset(x: vx, y: vy)
        )
    }
  }
}

#Preview {
  if let testImage = NSImage(systemSymbolName: "photo", accessibilityDescription: nil) {
    ZoomableImageView(image: testImage)
      .environmentObject(AppSettings())
      .frame(width: 400, height: 300)
  } else {
    Text("preview_image_load_failed".localized)
  }
}
