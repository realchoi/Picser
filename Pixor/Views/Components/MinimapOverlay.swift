//
//  MinimapOverlay.swift
//  Pixor
//
//  Extracted from ZoomableImageView.
//

import SwiftUI

// MARK: - Minimap Overlay
/// 右下角的小地图缩略视图，展示原图及当前视口位置
struct MinimapOverlay: View {
  let image: NSImage
  let containerSize: CGSize
  let visibleRectInImage: CGRect // 在原图坐标中的可见区域
  let transform: ImageTransform   // 与主图一致的旋转/镜像

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
        borderWidth: borderWidth,
        transform: transform
      )
      .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
    }
    .frame(width: containerSize.width, height: containerSize.height)
    .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 2)
    // 平滑过渡主图的旋转/镜像变化
    .animation(Motion.Anim.minimap, value: transform)
  }
}

/// 小地图主体内容：计算缩略图适配尺寸并绘制视口矩形
struct MinimapContent: View {
  let image: NSImage
  let containerSize: CGSize
  let contentPadding: CGFloat
  let visibleRectInImage: CGRect
  let viewportStrokeColor: Color
  let viewportFillColor: Color
  let borderWidth: CGFloat
  let transform: ImageTransform

  var body: some View {
    // 计算缩略图适配结果
    let iw = max(1.0, image.size.width)
    let ih = max(1.0, image.size.height)
    let cw = max(1.0, containerSize.width - contentPadding * 2)
    let ch = max(1.0, containerSize.height - contentPadding * 2)
    // 以旋转后的尺寸为准计算适配比例，确保旋转后完整显示在容器内
    let effW: CGFloat = (transform.rotation == .deg90 || transform.rotation == .deg270) ? ih : iw
    let effH: CGFloat = (transform.rotation == .deg90 || transform.rotation == .deg270) ? iw : ih
    let fitScale = min(cw / effW, ch / effH)
    // 旋转前（原始朝向）的缩放尺寸
    let miniW = iw * fitScale
    let miniH = ih * fitScale
    // 在容器中居中（以未旋转的尺寸计算偏移；旋转后整体一起居中）
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

      // 视口矩形（与图片同一坐标系，随后一起变换）
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
    // 应用与主图一致的视觉变换
    .rotationEffect(.degrees(transform.rotation.degrees))
    .scaleEffect(x: transform.mirrorH ? -1 : 1, y: transform.mirrorV ? -1 : 1, anchor: .center)
    .animation(Motion.Anim.minimap, value: transform)
  }
}
