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
              let clampedScale = PanZoomMath.scaleByWheel(
                current: scale,
                deltaY: deltaY,
                sensitivity: appSettings.zoomSensitivity,
                min: minScale,
                max: maxScale
              )

              withAnimation(.easeInOut(duration: 0.1)) {
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
                  imageSize: image.size,
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
                  imageSize: image.size,
                  baseFitScale: baseFitScale,
                  scale: scale
                )
                let proposed = CGSize(
                  width: lastOffset.width + value.translation.width,
                  height: lastOffset.height + value.translation.height
                )
                let clamped = PanZoomMath.clamp(offset: proposed, to: maxOffset)
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
                let clamped = PanZoomMath.scaleByMagnification(
                  last: lastScale,
                  gestureValue: value,
                  min: minScale,
                  max: maxScale
                )
                withAnimation(.easeInOut(duration: 0.08)) {
                  scale = clamped
                  // 缩放后更新并夹取偏移，避免越界
                  let maxOffset = PanZoomMath.maxOffset(
                    viewSize: geometry.size,
                    imageSize: image.size,
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
                  imageSize: image.size,
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
          imageSize: image.size,
          baseFitScale: baseFitScale,
          scale: scale
        )
          && appSettings.showMinimap
          && (appSettings.minimapAutoHideSeconds <= 0 || minimapUserVisible)
        {
          let visRect = PanZoomMath.visibleRectInImage(
            viewSize: geometry.size,
            imageSize: image.size,
            offset: offset,
            baseFitScale: baseFitScale,
            scale: scale
          )
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
    withAnimation(.easeInOut(duration: 0.3)) {
      scale = t.scale
      lastScale = t.lastScale
      offset = t.offset
      lastOffset = t.lastOffset
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

    if let (fit, transform) = PanZoomMath.fitAndDefaultTransform(viewSize: viewSize, imageSize: imageSize) {
      baseFitScale = fit
      withAnimation(.easeInOut(duration: 0.25)) {
        scale = transform.scale
        lastScale = transform.lastScale
        offset = transform.offset
        lastOffset = transform.lastOffset
        invalidateCache()
      }
    } else {
      let t = PanZoomMath.defaultTransform()
      scale = t.scale
      lastScale = t.lastScale
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
    return PanZoomMath.maxOffset(
      viewSize: geometry.size,
      imageSize: image.size,
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
    ZoomableImageView(image: testImage)
      .environmentObject(AppSettings())
      .frame(width: 400, height: 300)
  } else {
    Text("preview_image_load_failed".localized)
  }
}
