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
  // 裁剪开关与比例（默认关闭）
  var isCropping: Bool = false
  var cropAspect: CropAspectOption = .freeform

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

  // MARK: - 裁剪状态
  @State private var cropRect: CGRect?
  @State private var cropDragStartRect: CGRect?
  @State private var activeCropHandle: CropHandle?
  @State private var cropControlSize: CGSize = .zero
  @State private var isCropHandleDragging: Bool = false // 拖动裁剪手柄时禁止控制栏拦截事件
  private let cropBorderColor = Color.accentColor
  private let cropHandleSize: CGFloat = 14
  private let cropBorderWidth: CGFloat = 2.0
  private let minCropSide: CGFloat = 60
  private let cropEdgeHitThickness: CGFloat = 12
  private let cropControlSpacing: CGFloat = 16
  private let cropControlSafeMargin: CGFloat = 12

  var cropControls: CropControlConfiguration? = nil

  private var effectiveScale: CGFloat {
    scale
  }

  private var effectiveOffset: CGSize {
    offset
  }

  var body: some View {
    GeometryReader { geometry in
      let imageView = AnimatableImageView(image: image)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .rotationEffect(.degrees(transform.rotation.degrees))
        .scaleEffect(x: transform.mirrorH ? -1 : 1, y: transform.mirrorV ? -1 : 1, anchor: .center)
        .scaleEffect(effectiveScale)
        .offset(effectiveOffset)
        .overlay(
          ScrollWheelHandler { deltaY in
            guard shouldRespondToZoomGesture() else { return }
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
              let maxOffset = getCachedMaxOffset(geometry: geometry)
              offset = PanZoomMath.clamp(offset: offset, to: maxOffset)
              lastOffset = PanZoomMath.clamp(offset: lastOffset, to: maxOffset)
              cacheMaxOffset(maxOffset, for: clampedScale)
            }
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
      ZStack {
        imageView

        if isCropping {
          cropOverlay(geometry: geometry)
            .allowsHitTesting(true)
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
        // 切换图片时清除裁剪框
        cropRect = nil
        cropDragStartRect = nil
        activeCropHandle = nil
        isCropHandleDragging = false
      }
      .onChange(of: transform) { _, _ in
        // 旋转/镜像改变时根据新有效尺寸重新适配
        fitImageToView(geometry: geometry)
      }
      .onChange(of: isCropping) { _, newValue in
        if newValue {
          // 进入裁剪模式时，重置平移并初始化裁剪框，确保选区位于可见区域内
          resetPan()
          setupCropRect(in: geometry)
          activeCropHandle = nil
          isCropHandleDragging = false
        } else {
          cropRect = nil
          cropDragStartRect = nil
          activeCropHandle = nil
          cropControlSize = .zero
          isCropHandleDragging = false
        }
      }
      .onChange(of: cropAspect) { _, _ in
        // 更换比例时，保持中心点，按新比例自适应
        if isCropping { updateCropRectForAspect(in: geometry) }
      }
      .onReceive(NotificationCenter.default.publisher(for: .cropCommitRequested)) { _ in
        guard isCropping, let rect = cropRect else { return }
        let rotated = rotatedImageRect(from: rect, geometry: geometry)
        let original = mapRotatedRectToOriginal(rotated).integral
        NotificationCenter.default.post(
          name: .cropRectPrepared,
          object: nil,
          userInfo: ["rect": NSValue(rect: original)]
        )
      }
      .onChange(of: geometry.size) { _, _ in
        if isCropping {
          updateCropRectForAspect(in: geometry)
        }
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
      isCropHandleDragging = false
    }
  }

  // MARK: - 私有方法

  /// 检查是否应该响应缩放手势（修饰键检测）
  private func shouldRespondToZoomGesture() -> Bool {
    if isCropping { return false }
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
    if isCropping { return false }
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

  // MARK: - 裁剪覆盖层与逻辑

  /// 构建裁剪覆盖层：在可见范围内绘制裁剪框及手柄
  @ViewBuilder
  private func cropOverlay(geometry: GeometryProxy) -> some View {
    let viewBounds = CGRect(origin: .zero, size: geometry.size)
    let imageBounds = imageFrame(in: geometry).intersection(viewBounds)

    return ZStack(alignment: .topLeading) {
      Canvas { ctx, size in
        var bg = Path(CGRect(origin: .zero, size: size))
        if let rect = cropRect {
          bg.addRect(rect)
          ctx.fill(bg, with: .color(Color.black.opacity(0.45)), style: FillStyle(eoFill: true))
        } else {
          ctx.fill(bg, with: .color(Color.black.opacity(0.35)))
        }
      }
      .frame(width: geometry.size.width, height: geometry.size.height)
      .allowsHitTesting(false)

      if let rect = cropRect {
        cropSelectionLayer(for: rect, bounds: imageBounds, geometry: geometry)

        if let controls = cropControls {
          let config = CropControlConfiguration(
            customRatios: controls.customRatios,
            currentAspect: cropAspect,
            onSelectPreset: controls.onSelectPreset,
            onSelectCustomRatio: controls.onSelectCustomRatio,
            onAddCustomRatio: controls.onAddCustomRatio,
            onSave: controls.onSave,
            onCancel: controls.onCancel
          )

          let size = cropControlSize.width > 0 && cropControlSize.height > 0 ? cropControlSize : CGSize(width: 220, height: 48)
          let clampedCenterX = min(max(rect.midX, size.width / 2 + cropControlSafeMargin), geometry.size.width - size.width / 2 - cropControlSafeMargin)
          let centerY = resolveCropControlCenterY(rect: rect, geometrySize: geometry.size, controlSize: size)

          let frame = CGRect(
            x: clampedCenterX - size.width / 2,
            y: centerY - size.height / 2,
            width: size.width,
            height: size.height
          )

          CropControlBar(config: config)
            .readSize(into: $cropControlSize)
            .position(x: clampedCenterX, y: centerY)
            .zIndex(1)
            .allowsHitTesting(!isCropHandleDragging)
        }
      }
    }
    .frame(width: geometry.size.width, height: geometry.size.height)
    .onAppear { setupCropRectIfNeeded(in: geometry) }
  }

  /// 裁剪控制点类型
  private enum CropHandle {
    case move
    case topLeft, top, topRight, right, bottomRight, bottom, bottomLeft, left
  }

  /// 仅负责绘制选区和响应拖动的覆盖层
  @ViewBuilder
  private func cropSelectionLayer(for rect: CGRect, bounds: CGRect, geometry: GeometryProxy) -> some View {
    ZStack(alignment: .topLeading) {
      Rectangle()
        .fill(Color.clear)
        .contentShape(Rectangle())
        .frame(width: rect.width, height: rect.height)
        .position(x: rect.midX, y: rect.midY)
        .onHover { inside in
          if inside { NSCursor.openHand.set() } else { NSCursor.arrow.set() }
        }

      Rectangle()
        .stroke(cropBorderColor, lineWidth: cropBorderWidth)
        .frame(width: rect.width, height: rect.height)
        .position(x: rect.midX, y: rect.midY)

      handleViews(for: rect, bounds: bounds)
    }
    .frame(width: geometry.size.width, height: geometry.size.height)
    .contentShape(Rectangle())
    .highPriorityGesture(
      cropDragGesture(bounds: bounds)
    )
  }

  /// 绘制所有手柄
  @ViewBuilder
  private func handleViews(for rect: CGRect, bounds: CGRect) -> some View {
    let handles: [(CGPoint, CropHandle, NSCursor)] = [
      (CGPoint(x: rect.minX, y: rect.minY), .topLeft, .crosshair),
      (CGPoint(x: rect.midX, y: rect.minY), .top, .resizeUpDown),
      (CGPoint(x: rect.maxX, y: rect.minY), .topRight, .crosshair),
      (CGPoint(x: rect.maxX, y: rect.midY), .right, .resizeLeftRight),
      (CGPoint(x: rect.maxX, y: rect.maxY), .bottomRight, .crosshair),
      (CGPoint(x: rect.midX, y: rect.maxY), .bottom, .resizeUpDown),
      (CGPoint(x: rect.minX, y: rect.maxY), .bottomLeft, .crosshair),
      (CGPoint(x: rect.minX, y: rect.midY), .left, .resizeLeftRight)
    ]

    ForEach(0..<handles.count, id: \.self) { index in
      let item = handles[index]
      Rectangle()
        .fill(Color.white)
        .frame(width: cropHandleSize, height: cropHandleSize)
        .contentShape(Rectangle().inset(by: -6))
        .position(item.0)
        .overlay(
          Rectangle().stroke(Color.black.opacity(0.75), lineWidth: 1)
        )
        .onHover { inside in
          if inside { item.2.set() } else { NSCursor.arrow.set() }
        }
    }

    let edgeRects: [(CGRect, CropHandle, NSCursor)] = [
      (
        CGRect(
          x: rect.minX + cropHandleSize / 2,
          y: rect.minY - cropEdgeHitThickness / 2,
          width: max(0, rect.width - cropHandleSize),
          height: cropEdgeHitThickness
        ), .top, .resizeUpDown
      ),
      (
        CGRect(
          x: rect.minX + cropHandleSize / 2,
          y: rect.maxY - cropEdgeHitThickness / 2,
          width: max(0, rect.width - cropHandleSize),
          height: cropEdgeHitThickness
        ), .bottom, .resizeUpDown
      ),
      (
        CGRect(
          x: rect.minX - cropEdgeHitThickness / 2,
          y: rect.minY + cropHandleSize / 2,
          width: cropEdgeHitThickness,
          height: max(0, rect.height - cropHandleSize)
        ), .left, .resizeLeftRight
      ),
      (
        CGRect(
          x: rect.maxX - cropEdgeHitThickness / 2,
          y: rect.minY + cropHandleSize / 2,
          width: cropEdgeHitThickness,
          height: max(0, rect.height - cropHandleSize)
        ), .right, .resizeLeftRight
      )
    ]

    ForEach(0..<edgeRects.count, id: \.self) { index in
      let edge = edgeRects[index]
      Rectangle()
        .fill(Color.clear)
        .frame(width: edge.0.width, height: edge.0.height)
        .position(x: edge.0.midX, y: edge.0.midY)
        .contentShape(Rectangle())
        .onHover { inside in
          if inside { edge.2.set() } else { NSCursor.arrow.set() }
        }
    }
  }

  private func cropDragGesture(bounds: CGRect) -> some Gesture {
    DragGesture(minimumDistance: 0)
      .onChanged { value in
        guard let currentRect = cropRect else { return }
        if cropDragStartRect == nil {
          cropDragStartRect = currentRect
          let handle = detectHandle(at: value.startLocation, in: currentRect)
          if let handle {
            activeCropHandle = handle
            isCropHandleDragging = true
          } else {
            cropDragStartRect = nil
            activeCropHandle = nil
            isCropHandleDragging = false
            return
          }
        }
        guard let handle = activeCropHandle, let baseRect = cropDragStartRect else { return }

        let translation = value.translation
        let updated: CGRect
        if handle == .move {
          var rect = baseRect
          rect.origin.x += translation.width
          rect.origin.y += translation.height
          updated = clampRect(rect, within: bounds)
          NSCursor.closedHand.set()
        } else {
          updated = rectForHandle(handle: handle, base: baseRect, translation: translation, bounds: bounds)
        }
        cropRect = updated
      }
      .onEnded { _ in
        if let rect = cropRect {
          cropRect = clampRect(rect, within: bounds)
        }
        cropDragStartRect = nil
        activeCropHandle = nil
        isCropHandleDragging = false
        NSCursor.arrow.set()
      }
  }

  private func detectHandle(at point: CGPoint, in rect: CGRect) -> CropHandle? {
    let cornerTolerance = cropHandleSize + 8
    let edgeTolerance = max(cropEdgeHitThickness, 14)

    if !rect.insetBy(dx: -edgeTolerance, dy: -edgeTolerance).contains(point) {
      return nil
    }

    if abs(point.x - rect.minX) <= cornerTolerance && abs(point.y - rect.minY) <= cornerTolerance { return .topLeft }
    if abs(point.x - rect.maxX) <= cornerTolerance && abs(point.y - rect.minY) <= cornerTolerance { return .topRight }
    if abs(point.x - rect.minX) <= cornerTolerance && abs(point.y - rect.maxY) <= cornerTolerance { return .bottomLeft }
    if abs(point.x - rect.maxX) <= cornerTolerance && abs(point.y - rect.maxY) <= cornerTolerance { return .bottomRight }

    if abs(point.y - rect.minY) <= edgeTolerance { return .top }
    if abs(rect.maxY - point.y) <= edgeTolerance { return .bottom }
    if abs(point.x - rect.minX) <= edgeTolerance { return .left }
    if abs(rect.maxX - point.x) <= edgeTolerance { return .right }

    if rect.contains(point) {
      return .move
    }

    return nil
  }

  private func rectForHandle(handle: CropHandle, base: CGRect, translation: CGSize, bounds: CGRect) -> CGRect {
    var rect = base

    switch handle {
    case .move:
      return clampRect(base, within: bounds)
    case .topLeft:
      rect.origin.x += translation.width
      rect.origin.y += translation.height
      rect.size.width -= translation.width
      rect.size.height -= translation.height
    case .topRight:
      rect.origin.y += translation.height
      rect.size.width += translation.width
      rect.size.height -= translation.height
    case .bottomLeft:
      rect.origin.x += translation.width
      rect.size.width -= translation.width
      rect.size.height += translation.height
    case .bottomRight:
      rect.size.width += translation.width
      rect.size.height += translation.height
    case .top:
      rect.origin.y += translation.height
      rect.size.height -= translation.height
    case .bottom:
      rect.size.height += translation.height
    case .left:
      rect.origin.x += translation.width
      rect.size.width -= translation.width
    case .right:
      rect.size.width += translation.width
    }

    rect.size.width = max(rect.size.width, 1)
    rect.size.height = max(rect.size.height, 1)

    // minimum size adjustments
    if rect.width < minCropSide {
      let delta = minCropSide - rect.width
      rect.size.width = minCropSide
      if [.topLeft, .bottomLeft, .left].contains(handle) {
        rect.origin.x -= delta
      }
    }
    if rect.height < minCropSide {
      let delta = minCropSide - rect.height
      rect.size.height = minCropSide
      if [.topLeft, .topRight, .top].contains(handle) {
        rect.origin.y -= delta
      }
    }

    if let aspect = currentAspectValue() {
      rect = enforceAspect(rect: rect, base: base, handle: handle, aspect: aspect)
    }

    return clampRect(rect, within: bounds)
  }

  private func enforceAspect(rect: CGRect, base: CGRect, handle: CropHandle, aspect: CGFloat) -> CGRect {
    var result = rect

    switch handle {
    case .move:
      return rect
    case .topLeft:
      let anchor = CGPoint(x: base.maxX, y: base.maxY)
      var width = max(minCropSide, anchor.x - result.origin.x)
      var height = width / aspect
      if result.origin.y > anchor.y - height {
        height = max(minCropSide, anchor.y - result.origin.y)
        width = height * aspect
      }
      result = CGRect(x: anchor.x - width, y: anchor.y - height, width: width, height: height)
    case .topRight:
      let anchor = CGPoint(x: base.minX, y: base.maxY)
      var width = max(minCropSide, result.maxX - anchor.x)
      var height = width / aspect
      if result.origin.y > anchor.y - height {
        height = max(minCropSide, anchor.y - result.origin.y)
        width = height * aspect
      }
      result = CGRect(x: anchor.x, y: anchor.y - height, width: width, height: height)
    case .bottomLeft:
      let anchor = CGPoint(x: base.maxX, y: base.minY)
      var width = max(minCropSide, anchor.x - result.origin.x)
      var height = width / aspect
      if result.maxY < anchor.y + height {
        height = max(minCropSide, result.maxY - anchor.y)
        width = height * aspect
      }
      result = CGRect(x: anchor.x - width, y: anchor.y, width: width, height: height)
    case .bottomRight:
      let anchor = CGPoint(x: base.minX, y: base.minY)
      var width = max(minCropSide, result.maxX - anchor.x)
      var height = width / aspect
      if result.maxY < anchor.y + height {
        height = max(minCropSide, result.maxY - anchor.y)
        width = height * aspect
      }
      result = CGRect(x: anchor.x, y: anchor.y, width: width, height: height)
    case .top:
      let anchor = CGPoint(x: base.midX, y: base.maxY)
      var height = max(minCropSide, anchor.y - result.origin.y)
      var width = height * aspect
      result = CGRect(x: anchor.x - width / 2, y: anchor.y - height, width: width, height: height)
    case .bottom:
      let anchor = CGPoint(x: base.midX, y: base.minY)
      var height = max(minCropSide, result.maxY - anchor.y)
      var width = height * aspect
      result = CGRect(x: anchor.x - width / 2, y: anchor.y, width: width, height: height)
    case .left:
      let anchor = CGPoint(x: base.maxX, y: base.midY)
      var width = max(minCropSide, anchor.x - result.origin.x)
      var height = width / aspect
      result = CGRect(x: anchor.x - width, y: anchor.y - height / 2, width: width, height: height)
    case .right:
      let anchor = CGPoint(x: base.minX, y: base.midY)
      var width = max(minCropSide, result.maxX - anchor.x)
      var height = width / aspect
      result = CGRect(x: anchor.x, y: anchor.y - height / 2, width: width, height: height)
    }

    return result
  }

  /// 夹取到可见范围
  private func clampRect(_ rect: CGRect, within frame: CGRect) -> CGRect {
    guard !frame.isEmpty else { return rect }
    let width = min(max(rect.width, minCropSide), frame.width)
    let height = min(max(rect.height, minCropSide), frame.height)
    var x = rect.origin.x
    var y = rect.origin.y
    if x < frame.minX { x = frame.minX }
    if y < frame.minY { y = frame.minY }
    if x + width > frame.maxX { x = frame.maxX - width }
    if y + height > frame.maxY { y = frame.maxY - height }
    return CGRect(x: x, y: y, width: width, height: height)
  }

  /// 计算裁剪控制条的垂直中心位置，尽量避开裁剪框底部手柄
  private func resolveCropControlCenterY(rect: CGRect, geometrySize: CGSize, controlSize: CGSize) -> CGFloat {
    let safeMargin = cropControlSafeMargin
    let lowerBound = controlSize.height / 2 + safeMargin
    let upperBound = max(lowerBound, geometrySize.height - controlSize.height / 2 - safeMargin)

    let desiredBelow = rect.maxY + cropControlSpacing + controlSize.height / 2
    if desiredBelow <= upperBound {
      return max(desiredBelow, lowerBound)
    }

    let desiredAbove = rect.minY - cropControlSpacing - controlSize.height / 2
    if desiredAbove >= lowerBound {
      return min(desiredAbove, upperBound)
    }

    let clampedBelow = min(desiredBelow, upperBound)
    return max(clampedBelow, lowerBound)
  }

  private func setupCropRectIfNeeded(in geometry: GeometryProxy) {
    guard isCropping else { return }
    if cropRect == nil {
      setupCropRect(in: geometry)
    }
  }

  private func setupCropRect(in geometry: GeometryProxy) {
    let frame = imageFrame(in: geometry).intersection(CGRect(origin: .zero, size: geometry.size))
    guard !frame.isEmpty else { cropRect = nil; return }
    let rect = clampRect(defaultCropRect(in: frame), within: frame)
    cropRect = rect
    cropDragStartRect = nil
    activeCropHandle = nil
    isCropHandleDragging = false
  }

  private func defaultCropRect(in frame: CGRect) -> CGRect {
    let fraction: CGFloat = 0.82
    var width = frame.width * fraction
    var height = frame.height * fraction
    if let aspect = currentAspectValue() {
      let frameAspect = frame.width / frame.height
      if frameAspect > aspect {
        height = min(frame.height, height)
        width = height * aspect
      } else {
        width = min(frame.width, width)
        height = width / aspect
      }
    }
    width = min(max(width, minCropSide), frame.width)
    height = min(max(height, minCropSide), frame.height)
    let origin = CGPoint(x: frame.midX - width / 2, y: frame.midY - height / 2)
    return CGRect(origin: origin, size: CGSize(width: width, height: height))
  }

  private func updateCropRectForAspect(in geometry: GeometryProxy) {
    let frame = imageFrame(in: geometry).intersection(CGRect(origin: .zero, size: geometry.size))
    guard !frame.isEmpty else { cropRect = nil; return }
    guard let current = cropRect else {
      cropRect = defaultCropRect(in: frame)
      return
    }

    let center = CGPoint(x: current.midX, y: current.midY)
    let aspect = currentAspectValue()
    var width = min(max(current.width, minCropSide), frame.width)
    var height = min(max(current.height, minCropSide), frame.height)

    if let aspect {
      if width / height > aspect {
        height = width / aspect
        if height > frame.height {
          height = frame.height
          width = height * aspect
        }
      } else {
        width = height * aspect
        if width > frame.width {
          width = frame.width
          height = width / aspect
        }
      }
    }

    var rect = CGRect(x: center.x - width / 2, y: center.y - height / 2, width: width, height: height)
    rect = clampRect(rect, within: frame)
    cropRect = rect
  }

  private func currentAspectValue() -> CGFloat? {
    switch cropAspect {
    case .freeform:
      return nil
    case .original:
      let eff = effectiveImageSize()
      guard eff.width > 0, eff.height > 0 else { return nil }
      return eff.width / eff.height
    case .fixed(let ratio):
      let value = ratio.value
      return value > 0 ? CGFloat(value) : nil
    }
  }

  /// 图像在视图中的完整边界（包含不可见部分）
  private func imageFrame(in geometry: GeometryProxy) -> CGRect {
    let eff = effectiveImageSize()
    let displayWidth = eff.width * baseFitScale * scale
    let displayHeight = eff.height * baseFitScale * scale
    let center = CGPoint(x: geometry.size.width / 2 + offset.width, y: geometry.size.height / 2 + offset.height)
    return CGRect(
      x: center.x - displayWidth / 2,
      y: center.y - displayHeight / 2,
      width: max(0, displayWidth),
      height: max(0, displayHeight)
    )
  }

  /// 将视图坐标中的裁剪矩形映射到“旋转后”图像坐标
  private func rotatedImageRect(from viewRect: CGRect, geometry: GeometryProxy) -> CGRect {
    let frame = imageFrame(in: geometry)
    guard frame.width > 0, frame.height > 0 else { return .zero }
    let eff = effectiveImageSize()

    let x0 = (viewRect.minX - frame.minX) / frame.width * eff.width
    let y0 = (viewRect.minY - frame.minY) / frame.height * eff.height
    let x1 = (viewRect.maxX - frame.minX) / frame.width * eff.width
    let y1 = (viewRect.maxY - frame.minY) / frame.height * eff.height

    let minX = max(0, min(x0, x1))
    let minY = max(0, min(y0, y1))
    let maxX = min(eff.width, max(x0, x1))
    let maxY = min(eff.height, max(y0, y1))

    return CGRect(x: minX, y: minY, width: max(0, maxX - minX), height: max(0, maxY - minY))
  }

  /// 将“旋转后”的裁剪矩形映射回原图坐标（包含镜像）
  private func mapRotatedRectToOriginal(_ r: CGRect) -> CGRect {
    let originalSize = image.size
    let effSize = effectiveImageSize()

    var rm = r
    if transform.mirrorH {
      rm.origin.x = max(0, effSize.width - (r.origin.x + r.size.width))
    }
    if transform.mirrorV {
      rm.origin.y = max(0, effSize.height - (r.origin.y + r.size.height))
    }

    switch transform.rotation {
    case .deg0:
      return rm
    case .deg90:
      return CGRect(
        x: max(0, originalSize.width - (rm.origin.y + rm.size.height)),
        y: max(0, rm.origin.x),
        width: max(0, rm.size.height),
        height: max(0, rm.size.width)
      )
    case .deg180:
      return CGRect(
        x: max(0, originalSize.width - (rm.origin.x + rm.size.width)),
        y: max(0, originalSize.height - (rm.origin.y + rm.size.height)),
        width: max(0, rm.size.width),
        height: max(0, rm.size.height)
      )
    case .deg270:
      return CGRect(
        x: max(0, rm.origin.y),
        y: max(0, originalSize.height - (rm.origin.x + rm.size.width)),
        width: max(0, rm.size.height),
        height: max(0, rm.size.width)
      )
    }
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
