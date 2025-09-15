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
  let transform: ImageTransform

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
          // 先应用旋转和镜像，再应用缩放和平移，使交互手感一致
          .rotationEffect(.degrees(transform.rotation.degrees))
          .scaleEffect(x: transform.mirrorH ? -1 : 1, y: transform.mirrorV ? -1 : 1, anchor: .center)
          .scaleEffect(effectiveScale)
          .offset(effectiveOffset)
          // 使用overlay添加滚轮处理
          .overlay(
            ScrollWheelHandler { deltaY in
              // 检查是否应该响应滚轮缩放（修饰键检测）
              guard shouldRespondToZoomGesture() else { return }

              // 处理滚轮缩放
              let clampedScale = PanZoomMath.scaleByWheel(
                current: scale,
                deltaY: deltaY,
                sensitivity: appSettings.zoomSensitivity,
                min: minScale,
                max: maxScale
              )

              withAnimation(Motion.Anim.fast) {
                scale = clampedScale
                lastScale = clampedScale
                // 缩放后约束偏移量，防止越界
                // 使用缓存的 maxOffset 避免重复计算
                let maxOffset = getCachedMaxOffset(geometry: geometry)
                offset = PanZoomMath.clamp(offset: offset, to: maxOffset)
                lastOffset = PanZoomMath.clamp(offset: lastOffset, to: maxOffset)
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
                let maxOffset = PanZoomMath.maxOffset(
                  viewSize: geometry.size,
                  imageSize: effectiveImageSize(),
                  baseFitScale: baseFitScale,
                  scale: scale
                )
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
                offset = PanZoomMath.clamp(offset: proposed, to: maxOffset)
                // 拖拽过程中刷新小地图可见性
                triggerMinimapAutoHide()
              }
              .onEnded { value in
                // 检查是否应该响应拖拽（修饰键检测）
                guard shouldRespondToPanGesture() else { return }
                let maxOffset = PanZoomMath.maxOffset(
                  viewSize: geometry.size,
                  imageSize: effectiveImageSize(),
                  baseFitScale: baseFitScale,
                  scale: scale
                )
                let proposed = CGSize(
                  width: lastOffset.width + value.translation.width,
                  height: lastOffset.height + value.translation.height
                )
                let clamped = PanZoomMath.clamp(offset: proposed, to: maxOffset)
                withAnimation(Motion.Anim.panEnd) {
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
                let clamped = PanZoomMath.scaleByMagnification(
                  last: lastScale,
                  gestureValue: value,
                  min: minScale,
                  max: maxScale
                )
                withAnimation(Motion.Anim.ultraFast) {
                  scale = clamped
                  // 缩放后更新并夹取偏移，避免越界
                  let maxOffset = PanZoomMath.maxOffset(
                    viewSize: geometry.size,
                    imageSize: effectiveImageSize(),
                    baseFitScale: baseFitScale,
                    scale: scale
                  )
                  offset = PanZoomMath.clamp(offset: offset, to: maxOffset)
                }
                // 捏合过程中刷新小地图可见性
                triggerMinimapAutoHide()
              }
              .onEnded { value in
                // 结束时固化缩放比例，并同步偏移缓存
                let clamped = PanZoomMath.scaleByMagnification(
                  last: lastScale,
                  gestureValue: value,
                  min: minScale,
                  max: maxScale
                )
                lastScale = clamped
                let maxOffset = PanZoomMath.maxOffset(
                  viewSize: geometry.size,
                  imageSize: effectiveImageSize(),
                  baseFitScale: baseFitScale,
                  scale: scale
                )
                lastOffset = PanZoomMath.clamp(offset: offset, to: maxOffset)
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
        if PanZoomMath.shouldShowMinimap(
          viewSize: geometry.size,
          imageSize: effectiveImageSize(),
          baseFitScale: baseFitScale,
          scale: scale
        )
          && appSettings.showMinimap
          && (appSettings.minimapAutoHideSeconds <= 0 || minimapUserVisible)
        {
          let visRect = visibleRectInOriginalImage(geometry: geometry)
          MinimapOverlay(
            image: image,
            containerSize: CGSize(width: 180, height: 140),
            visibleRectInImage: visRect,
            transform: transform
          )
          .padding(10)
          .transition(.opacity.combined(with: .move(edge: .bottom)))
          .animation(Motion.Anim.standard, value: visRect)
          .animation(Motion.Anim.minimap, value: transform)
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
      .onChange(of: transform) { _, _ in
        // 旋转/镜像改变时根据新有效尺寸重新适配
        fitImageToView(geometry: geometry)
      }
    }
    .onChange(of: appSettings.minZoomScale) { _, newValue in
      minScale = newValue
      scale = PanZoomMath.ensureScale(scale, min: minScale, max: maxScale)
      invalidateCache()  // 缩放限制变化时清除缓存
    }
    .onChange(of: appSettings.maxZoomScale) { _, newValue in
      maxScale = newValue
      scale = PanZoomMath.ensureScale(scale, min: minScale, max: maxScale)
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

  /// 重置缩放
  private func resetZoom() {
    let t = PanZoomMath.defaultTransform()
    withAnimation(Motion.Anim.reset) {
      scale = t.scale
      lastScale = t.lastScale
      offset = t.offset
      lastOffset = t.lastOffset
      invalidateCache()
    }
  }

  /// 重置拖拽
  private func resetPan() {
    withAnimation(Motion.Anim.reset) {
      offset = .zero
      lastOffset = .zero
    }
  }

  /// 适应窗口大小：记录基础适配比例，并将相对缩放恢复为1（即刚好适配）
  private func fitImageToView(geometry: GeometryProxy) {
    let viewSize = geometry.size
    let imageSize = effectiveImageSize()

    if let (fit, resetT) = PanZoomMath.fitAndDefaultTransform(viewSize: viewSize, imageSize: imageSize) {
      baseFitScale = fit
      withAnimation(Motion.Anim.slow) {
        scale = resetT.scale
        lastScale = resetT.lastScale
        offset = resetT.offset
        lastOffset = resetT.lastOffset
        invalidateCache()
      }
    } else {
      let t = PanZoomMath.defaultTransform()
      scale = t.scale
      lastScale = t.lastScale
    }
  }

  /// 根据旋转得到有效的图像尺寸（90/270 度时交换宽高）
  private func effectiveImageSize() -> CGSize {
    let s = image.size
    switch transform.rotation {
    case .deg90, .deg270:
      return CGSize(width: s.height, height: s.width)
    default:
      return s
    }
  }

  /// 计算在原始图像坐标中的可见区域（考虑旋转与镜像）
  private func visibleRectInOriginalImage(geometry: GeometryProxy) -> CGRect {
    let originalSize = image.size
    let effSize = effectiveImageSize()
    // 先在“旋转后”的坐标系中计算可见区域（不考虑镜像，镜像不改变区域大小，仅改变原点位置）
    let r = PanZoomMath.visibleRectInImage(
      viewSize: geometry.size,
      imageSize: effSize,
      offset: offset,
      baseFitScale: baseFitScale,
      scale: scale
    )

    // 将旋转坐标系中的矩形映射回原始图像坐标（不在此处应用镜像；镜像在小地图视图中统一应用）
    let mapped: CGRect
    switch transform.rotation {
    case .deg0:
      mapped = r
    case .deg90: // 顺时针90°：x = W - (y' + h'), y = x', w = h', h = w'
      mapped = CGRect(
        x: max(0, originalSize.width - (r.origin.y + r.size.height)),
        y: max(0, r.origin.x),
        width: max(0, r.size.height),
        height: max(0, r.size.width)
      )
    case .deg180: // 180°：x = W - (x' + w'), y = H - (y' + h')
      mapped = CGRect(
        x: max(0, originalSize.width - (r.origin.x + r.size.width)),
        y: max(0, originalSize.height - (r.origin.y + r.size.height)),
        width: max(0, r.size.width),
        height: max(0, r.size.height)
      )
    case .deg270: // 逆时针90°：x = y', y = H - (x' + w'), w = h', h = w'
      mapped = CGRect(
        x: max(0, r.origin.y),
        y: max(0, originalSize.height - (r.origin.x + r.size.width)),
        width: max(0, r.size.height),
        height: max(0, r.size.width)
      )
    }

    // 夹取到原图范围内
    let x0 = max(0.0, mapped.origin.x)
    let y0 = max(0.0, mapped.origin.y)
    let x1 = min(originalSize.width, mapped.origin.x + mapped.size.width)
    let y1 = min(originalSize.height, mapped.origin.y + mapped.size.height)
    return CGRect(x: x0, y: y0, width: max(0, x1 - x0), height: max(0, y1 - y0))
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
    return PanZoomMath.maxOffset(
      viewSize: geometry.size,
      imageSize: effectiveImageSize(),
      baseFitScale: baseFitScale,
      scale: scale
    )
  }

  /// 清除缓存（在需要时调用）
  private func invalidateCache() {
    cachedMaxOffset = nil
  }

  // removed: shouldShowMinimap/currentVisibleRectInImage (moved to PanZoomMath)

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

#Preview {
  if let testImage = NSImage(systemSymbolName: "photo", accessibilityDescription: nil) {
    ZoomableImageView(image: testImage, transform: .identity)
      .environmentObject(AppSettings())
      .frame(width: 400, height: 300)
  } else {
    Text("preview_image_load_failed".localized)
  }
}
