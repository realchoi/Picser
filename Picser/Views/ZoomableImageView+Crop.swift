import SwiftUI
import AppKit

extension ZoomableImageView {
  // MARK: - 裁剪覆盖层与逻辑

  /// 构建裁剪覆盖层：在可见范围内绘制裁剪框及手柄
  @ViewBuilder
  func cropOverlay(geometry: GeometryProxy) -> some View {
    let viewBounds = CGRect(origin: .zero, size: geometry.size)
    let imageBounds = imageFrame(in: geometry).intersection(viewBounds)

    ZStack(alignment: .topLeading) {
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
            onDeleteCustomRatio: controls.onDeleteCustomRatio,
            onAddCustomRatio: controls.onAddCustomRatio,
            onSave: controls.onSave,
            onCancel: controls.onCancel
          )

          let size = cropControlSize.width > 0 && cropControlSize.height > 0 ? cropControlSize : CGSize(width: 220, height: 48)
          let clampedCenterX = min(max(rect.midX, size.width / 2 + cropControlSafeMargin), geometry.size.width - size.width / 2 - cropControlSafeMargin)
          let centerY = resolveCropControlCenterY(rect: rect, geometrySize: geometry.size, controlSize: size)

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
    .onDisappear {
      updateHoveredHandle(nil)
      NSCursor.arrow.set()
    }
  }

  /// 裁剪控制点类型（保持 `ZoomableImageView` 其他成员可见）
  enum CropHandle {
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
          if inside {
            if hoveredCropHandle == nil || hoveredCropHandle == .move {
              updateHoveredHandle(.move)
            }
          } else if hoveredCropHandle == .move {
            updateHoveredHandle(nil)
          }
        }

      Rectangle()
        .stroke(cropBorderColor, lineWidth: cropBorderWidth)
        .frame(width: rect.width, height: rect.height)
        .position(x: rect.midX, y: rect.midY)

      handleViews(for: rect, bounds: bounds)
    }
    .frame(width: geometry.size.width, height: geometry.size.height)
    .contentShape(Rectangle())
    .onChange(of: hoveredCropHandle) { _, newValue in applyCursor(for: newValue) }
    .onHover { inside in
      if !inside, hoveredCropHandle != nil {
        updateHoveredHandle(nil)
      }
    }
    .highPriorityGesture(
      cropDragGesture(bounds: bounds)
    )
  }

  /// 绘制所有手柄
  @ViewBuilder
  private func handleViews(for rect: CGRect, bounds: CGRect) -> some View {
    let handles: [(CGPoint, CropHandle)] = [
      (CGPoint(x: rect.minX, y: rect.minY), .topLeft),
      (CGPoint(x: rect.midX, y: rect.minY), .top),
      (CGPoint(x: rect.maxX, y: rect.minY), .topRight),
      (CGPoint(x: rect.maxX, y: rect.midY), .right),
      (CGPoint(x: rect.maxX, y: rect.maxY), .bottomRight),
      (CGPoint(x: rect.midX, y: rect.maxY), .bottom),
      (CGPoint(x: rect.minX, y: rect.maxY), .bottomLeft),
      (CGPoint(x: rect.minX, y: rect.midY), .left)
    ]

    ForEach(0..<handles.count, id: \.self) { index in
      let item = handles[index]
      Circle()
        .fill(Color.white)
        .frame(width: cropHandleSize, height: cropHandleSize)
        .overlay(
          Circle().stroke(Color.black.opacity(0.75), lineWidth: 1)
        )
        .contentShape(Circle().inset(by: -4))
        .position(item.0)
        .onHover { inside in
          if inside {
            updateHoveredHandle(item.1)
          } else if hoveredCropHandle == item.1 {
            updateHoveredHandle(.move)
          }
        }
    }

    let edgeRects: [(CGRect, CropHandle)] = [
      (
        CGRect(
          x: rect.minX + cropHandleSize / 2,
          y: rect.minY - cropEdgeHitThickness / 2,
          width: max(0, rect.width - cropHandleSize),
          height: cropEdgeHitThickness
        ), .top
      ),
      (
        CGRect(
          x: rect.minX + cropHandleSize / 2,
          y: rect.maxY - cropEdgeHitThickness / 2,
          width: max(0, rect.width - cropHandleSize),
          height: cropEdgeHitThickness
        ), .bottom
      ),
      (
        CGRect(
          x: rect.minX - cropEdgeHitThickness / 2,
          y: rect.minY + cropHandleSize / 2,
          width: cropEdgeHitThickness,
          height: max(0, rect.height - cropHandleSize)
        ), .left
      ),
      (
        CGRect(
          x: rect.maxX - cropEdgeHitThickness / 2,
          y: rect.minY + cropHandleSize / 2,
          width: cropEdgeHitThickness,
          height: max(0, rect.height - cropHandleSize)
        ), .right
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
          if inside {
            updateHoveredHandle(edge.1)
          } else if hoveredCropHandle == edge.1 {
            updateHoveredHandle(.move)
          }
        }
    }
  }

  private func applyCursor(for handle: CropHandle?) {
    if isCropHandleDragging, activeCropHandle == .move {
      return
    }
    cursor(for: handle).set()
  }

  private func updateHoveredHandle(_ handle: CropHandle?) {
    if hoveredCropHandle == handle {
      return
    }
    hoveredCropHandle = handle
  }

  private func cursor(for handle: CropHandle?) -> NSCursor {
    switch handle {
    case .move:
      return NSCursor.openHand
    case .top, .bottom:
      return NSCursor.resizeUpDown
    case .left, .right:
      return NSCursor.resizeLeftRight
    case .topLeft, .topRight, .bottomLeft, .bottomRight:
      return NSCursor.crosshair
    case .none:
      return NSCursor.arrow
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
            updateHoveredHandle(handle)
          } else {
            cropDragStartRect = nil
            activeCropHandle = nil
            isCropHandleDragging = false
            updateHoveredHandle(nil)
            return
          }
        }
        guard let handle = activeCropHandle, let baseRect = cropDragStartRect else { return }

        let aspect = currentAspectValue()
        let translation = value.translation
        let updated: CGRect
        if handle == .move {
          var rect = baseRect
          rect.origin.x += translation.width
          rect.origin.y += translation.height
          if aspect != nil {
            updated = clampRectPosition(rect, within: bounds)
          } else {
            updated = clampRect(rect, within: bounds)
          }
          updateHoveredHandle(.move)
          NSCursor.closedHand.set()
        } else {
          updated = rectForHandle(
            handle: handle,
            base: baseRect,
            translation: translation,
            bounds: bounds,
            aspect: aspect
          )
          applyCursor(for: handle)
        }
        cropRect = updated
      }
      .onEnded { value in
        if let rect = cropRect {
          let aspect = currentAspectValue()
          if let aspect {
            let handle = activeCropHandle ?? .move
            if handle == .move {
              cropRect = clampRectPosition(rect, within: bounds)
            } else {
              let baseRect = cropDragStartRect ?? rect
              cropRect = clampRect(rect, within: bounds, aspect: aspect, base: baseRect, handle: handle)
            }
          } else {
            cropRect = clampRect(rect, within: bounds)
          }
        }
        cropDragStartRect = nil
        activeCropHandle = nil
        isCropHandleDragging = false
        if let rect = cropRect {
          updateHoveredHandle(detectHandle(at: value.location, in: rect))
        } else {
          updateHoveredHandle(nil)
        }
        applyCursor(for: hoveredCropHandle)
      }
  }

  private func detectHandle(at point: CGPoint, in rect: CGRect) -> CropHandle? {
    let cornerTolerance = max(cropHandleSize + 6, 16)
    let edgeTolerance = max(cropEdgeHitThickness + 4, 12)

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

  private func rectForHandle(
    handle: CropHandle,
    base: CGRect,
    translation: CGSize,
    bounds: CGRect,
    aspect: CGFloat?
  ) -> CGRect {
    var rect = base

    if aspect != nil && handle != .move {
      let dx = abs(translation.width)
      let dy = abs(translation.height)
      let effectiveDelta: CGFloat
      switch handle {
      case .top, .bottom:
        effectiveDelta = dy
      case .left, .right:
        effectiveDelta = dx
      default:
        effectiveDelta = max(dx, dy)
      }
      if effectiveDelta < cropHandleActivationThreshold {
        return base
      }
    }

    switch handle {
    case .move:
      if aspect != nil {
        return clampRectPosition(base, within: bounds)
      }
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

    if let aspect {
      rect = enforceAspect(rect: rect, base: base, handle: handle, aspect: aspect)
      return clampRect(rect, within: bounds, aspect: aspect, base: base, handle: handle)
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
      let height = max(minCropSide, anchor.y - result.origin.y)
      let width = height * aspect
      result = CGRect(x: anchor.x - width / 2, y: anchor.y - height, width: width, height: height)
    case .bottom:
      let anchor = CGPoint(x: base.midX, y: base.minY)
      let height = max(minCropSide, result.maxY - anchor.y)
      let width = height * aspect
      result = CGRect(x: anchor.x - width / 2, y: anchor.y, width: width, height: height)
    case .left:
      let anchor = CGPoint(x: base.maxX, y: base.midY)
      let width = max(minCropSide, anchor.x - result.origin.x)
      let height = width / aspect
      result = CGRect(x: anchor.x - width, y: anchor.y - height / 2, width: width, height: height)
    case .right:
      let anchor = CGPoint(x: base.minX, y: base.midY)
      let width = max(minCropSide, result.maxX - anchor.x)
      let height = width / aspect
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

  private func clampRect(
    _ rect: CGRect,
    within frame: CGRect,
    aspect: CGFloat,
    base: CGRect,
    handle: CropHandle
  ) -> CGRect {
    guard !frame.isEmpty else { return rect }
    let anchor = anchorPoint(for: handle, base: base)
    let limits = aspectLimits(for: handle, anchor: anchor, bounds: frame)
    var candidates: [CGFloat] = [rect.width]
    if limits.width > 0 { candidates.append(limits.width) }
    if limits.height > 0 { candidates.append(limits.height * aspect) }
    let width = max(0, candidates.min() ?? rect.width)
    let height = width / aspect
    let size = CGSize(width: width, height: height)
    return rectFrom(anchor: anchor, size: size, handle: handle)
  }

  private func clampRectPosition(_ rect: CGRect, within frame: CGRect) -> CGRect {
    guard !frame.isEmpty else { return rect }
    var clamped = rect
    let maxX = max(frame.minX, frame.maxX - clamped.width)
    let maxY = max(frame.minY, frame.maxY - clamped.height)
    if clamped.origin.x < frame.minX {
      clamped.origin.x = frame.minX
    } else if clamped.origin.x > maxX {
      clamped.origin.x = maxX
    }
    if clamped.origin.y < frame.minY {
      clamped.origin.y = frame.minY
    } else if clamped.origin.y > maxY {
      clamped.origin.y = maxY
    }
    return clamped
  }

  private func anchorPoint(for handle: CropHandle, base: CGRect) -> CGPoint {
    switch handle {
    case .topLeft:
      return CGPoint(x: base.maxX, y: base.maxY)
    case .topRight:
      return CGPoint(x: base.minX, y: base.maxY)
    case .bottomLeft:
      return CGPoint(x: base.maxX, y: base.minY)
    case .bottomRight:
      return CGPoint(x: base.minX, y: base.minY)
    case .top:
      return CGPoint(x: base.midX, y: base.maxY)
    case .bottom:
      return CGPoint(x: base.midX, y: base.minY)
    case .left:
      return CGPoint(x: base.maxX, y: base.midY)
    case .right:
      return CGPoint(x: base.minX, y: base.midY)
    case .move:
      return CGPoint(x: base.midX, y: base.midY)
    }
  }

  private func aspectLimits(for handle: CropHandle, anchor: CGPoint, bounds: CGRect) -> CGSize {
    let leftSpace = anchor.x - bounds.minX
    let rightSpace = bounds.maxX - anchor.x
    let topSpace = anchor.y - bounds.minY
    let bottomSpace = bounds.maxY - anchor.y

    switch handle {
    case .topLeft:
      return CGSize(width: max(0, leftSpace), height: max(0, topSpace))
    case .topRight:
      return CGSize(width: max(0, rightSpace), height: max(0, topSpace))
    case .bottomLeft:
      return CGSize(width: max(0, leftSpace), height: max(0, bottomSpace))
    case .bottomRight:
      return CGSize(width: max(0, rightSpace), height: max(0, bottomSpace))
    case .top:
      let halfWidth = max(0, min(leftSpace, rightSpace))
      return CGSize(width: halfWidth * 2, height: max(0, topSpace))
    case .bottom:
      let halfWidth = max(0, min(leftSpace, rightSpace))
      return CGSize(width: halfWidth * 2, height: max(0, bottomSpace))
    case .left:
      let halfHeight = max(0, min(topSpace, bottomSpace))
      return CGSize(width: max(0, leftSpace), height: halfHeight * 2)
    case .right:
      let halfHeight = max(0, min(topSpace, bottomSpace))
      return CGSize(width: max(0, rightSpace), height: halfHeight * 2)
    case .move:
      return CGSize(width: bounds.width, height: bounds.height)
    }
  }

  private func rectFrom(anchor: CGPoint, size: CGSize, handle: CropHandle) -> CGRect {
    let width = size.width
    let height = size.height

    switch handle {
    case .topLeft:
      return CGRect(x: anchor.x - width, y: anchor.y - height, width: width, height: height)
    case .topRight:
      return CGRect(x: anchor.x, y: anchor.y - height, width: width, height: height)
    case .bottomLeft:
      return CGRect(x: anchor.x - width, y: anchor.y, width: width, height: height)
    case .bottomRight:
      return CGRect(x: anchor.x, y: anchor.y, width: width, height: height)
    case .top:
      return CGRect(x: anchor.x - width / 2, y: anchor.y - height, width: width, height: height)
    case .bottom:
      return CGRect(x: anchor.x - width / 2, y: anchor.y, width: width, height: height)
    case .left:
      return CGRect(x: anchor.x - width, y: anchor.y - height / 2, width: width, height: height)
    case .right:
      return CGRect(x: anchor.x, y: anchor.y - height / 2, width: width, height: height)
    case .move:
      return CGRect(origin: CGPoint(x: anchor.x - width / 2, y: anchor.y - height / 2), size: size)
    }
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

  func setupCropRect(in geometry: GeometryProxy) {
    let frame = imageFrame(in: geometry).intersection(CGRect(origin: .zero, size: geometry.size))
    guard !frame.isEmpty else { cropRect = nil; return }
    let rect = clampRect(defaultCropRect(in: frame), within: frame)
    cropRect = rect
    cropDragStartRect = nil
    activeCropHandle = nil
    isCropHandleDragging = false
    updateHoveredHandle(nil)
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

  func updateCropRectForAspect(in geometry: GeometryProxy) {
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
  func rotatedImageRect(from viewRect: CGRect, geometry: GeometryProxy) -> CGRect {
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
  func mapRotatedRectToOriginal(_ r: CGRect) -> CGRect {
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
