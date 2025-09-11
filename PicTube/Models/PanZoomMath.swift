//
//  PanZoomMath.swift
//  PicTube
//
//  Pure helpers for pan/zoom computations used by ZoomableImageView.
//

import CoreGraphics

enum PanZoomMath {
  struct Transform {
    let scale: CGFloat
    let lastScale: CGFloat
    let offset: CGSize
    let lastOffset: CGSize
  }

  /// Compute the base fit scale for an image to fully fit into the given view size.
  /// Returns nil when any dimension is invalid or zero.
  static func computeFitScale(viewSize: CGSize, imageSize: CGSize) -> CGFloat? {
    guard imageSize.width > 0, imageSize.height > 0, viewSize.width > 0, viewSize.height > 0 else {
      return nil
    }
    let scaleX = viewSize.width / imageSize.width
    let scaleY = viewSize.height / imageSize.height
    return min(scaleX, scaleY)
  }

  /// Provide a default transform that represents a reset state.
  static func defaultTransform() -> Transform {
    Transform(scale: 1.0, lastScale: 1.0, offset: .zero, lastOffset: .zero)
  }

  /// Compute base fit and return a default (reset) transform together.
  static func fitAndDefaultTransform(viewSize: CGSize, imageSize: CGSize) -> (baseFitScale: CGFloat, transform: Transform)? {
    guard let fit = computeFitScale(viewSize: viewSize, imageSize: imageSize) else { return nil }
    return (fit, defaultTransform())
  }

  /// Compute the maximum pan offsets allowed given current baseFitScale and scale.
  static func maxOffset(viewSize: CGSize, imageSize: CGSize, baseFitScale: CGFloat, scale: CGFloat) -> CGSize {
    let displayedWidth = imageSize.width * baseFitScale * scale
    let displayedHeight = imageSize.height * baseFitScale * scale
    let maxOffsetX = max(0, (displayedWidth - viewSize.width) / 2)
    let maxOffsetY = max(0, (displayedHeight - viewSize.height) / 2)
    return CGSize(width: maxOffsetX, height: maxOffsetY)
  }

  /// Clamp a proposed offset within allowed max offset bounds.
  static func clamp(offset: CGSize, to maxOffset: CGSize) -> CGSize {
    CGSize(
      width: max(-maxOffset.width, min(maxOffset.width, offset.width)),
      height: max(-maxOffset.height, min(maxOffset.height, offset.height))
    )
  }

  /// Ensure scale stays within [min, max].
  static func ensureScale(_ scale: CGFloat, min minScale: CGFloat, max maxScale: CGFloat) -> CGFloat {
    if scale < minScale { return minScale }
    if scale > maxScale { return maxScale }
    return scale
  }

  /// Whether the minimap should be shown: when displayed size exceeds viewport.
  static func shouldShowMinimap(viewSize: CGSize, imageSize: CGSize, baseFitScale: CGFloat, scale: CGFloat) -> Bool {
    let displayedWidth = imageSize.width * baseFitScale * scale
    let displayedHeight = imageSize.height * baseFitScale * scale
    return displayedWidth > viewSize.width + 0.5 || displayedHeight > viewSize.height + 0.5
  }

  /// Visible rect in image coordinates for a given view size, pan offset and scale.
  static func visibleRectInImage(
    viewSize: CGSize,
    imageSize: CGSize,
    offset: CGSize,
    baseFitScale: CGFloat,
    scale: CGFloat
  ) -> CGRect {
    let vw = viewSize.width
    let vh = viewSize.height
    let iw = imageSize.width
    let ih = imageSize.height
    guard iw > 0, ih > 0, vw > 0, vh > 0 else { return .zero }

    let sDisp = baseFitScale * scale
    let imgLeft = (-vw / 2.0 - offset.width) / sDisp + iw / 2.0
    let imgRight = (vw / 2.0 - offset.width) / sDisp + iw / 2.0
    let imgTop = (-vh / 2.0 - offset.height) / sDisp + ih / 2.0
    let imgBottom = (vh / 2.0 - offset.height) / sDisp + ih / 2.0

    let x0 = max(0.0, min(iw, imgLeft))
    let x1 = max(0.0, min(iw, imgRight))
    let y0 = max(0.0, min(ih, imgTop))
    let y1 = max(0.0, min(ih, imgBottom))

    return CGRect(x: x0, y: y0, width: max(0.0, x1 - x0), height: max(0.0, y1 - y0))
  }

  // MARK: - Scale helpers

  /// Clamp a proposed scale to [min, max].
  static func clampScale(_ proposed: CGFloat, min: CGFloat, max: CGFloat) -> CGFloat {
    if proposed < min { return min }
    if proposed > max { return max }
    return proposed
  }

  /// Compute next scale for a scroll-wheel event.
  /// - Parameters:
  ///   - current: current scale value
  ///   - deltaY: scroll delta (Double), positive means zoom in (consistent with caller)
  ///   - sensitivity: user setting, e.g. 0.05
  ///   - min/max: bounds
  static func scaleByWheel(current: CGFloat, deltaY: Double, sensitivity: Double, min: CGFloat, max: CGFloat) -> CGFloat {
    let zoomFactor = 1.0 + CGFloat(deltaY * sensitivity)
    let proposed = current * zoomFactor
    return clampScale(proposed, min: min, max: max)
  }

  /// Compute next scale for a magnification gesture.
  /// - Parameters:
  ///   - last: last committed scale before gesture began
  ///   - gestureValue: gesture relative scale (1.0 means unchanged)
  static func scaleByMagnification(last: CGFloat, gestureValue: CGFloat, min: CGFloat, max: CGFloat) -> CGFloat {
    let proposed = last * gestureValue
    return clampScale(proposed, min: min, max: max)
  }
}
