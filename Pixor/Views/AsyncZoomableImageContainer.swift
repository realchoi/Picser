//
//  AsyncZoomableImageContainer.swift
//  Pixor
//
//  Created by Eric Cai on 2025/8/21.
//

import AppKit
import SwiftUI

// MARK: - Constants
private enum DownsampleRequestConstants {
  // 上限以像素为单位；用于根据屏幕 scale 换算为点
  static let maxLongSidePixels: CGFloat = 3200.0
  // 短边像素下限，避免模糊
}

/// 渐进式加载主图：先显示快速缩略图，再无缝切换到全尺寸已解码图像
struct AsyncZoomableImageContainer: View {
  let url: URL
  let transform: ImageTransform
  let windowToken: UUID
  // 裁剪参数（向下传递到 ZoomableImageView）
  var isCropping: Bool = false
  var cropAspect: CropAspectOption = .freeform
  var cropControls: CropControlConfiguration? = nil

  // 我们现在只需要一个 State 来存储最终显示的图片
  @State private var displayImage: NSImage?
  @State private var isShowingFull: Bool = false
  @State private var loadTask: Task<Void, Never>?
  @State private var fullLoadTask: Task<Void, Never>?
  @State private var viewportSize: CGSize = .zero

  // 任务触发键：由 URL 和视口的离散尺寸组成，满足 Equatable
  private var taskKey: String {
    let w = Int(viewportSize.width.rounded())
    let h = Int(viewportSize.height.rounded())
    return url.absoluteString + "|" + String(w) + "x" + String(h)
  }

  var body: some View {
    GeometryReader { geometry in
      ZStack {
        if let image = displayImage {
          ZoomableImageView(
            image: image,
            transform: transform,
            windowToken: windowToken,
            isCropping: isCropping,
            cropAspect: cropAspect,
            cropControls: cropControls
          )
        } else {
          // 保持加载中的占位符
          Rectangle()
            .fill(Color.secondary.opacity(0.1))
            .overlay(ProgressView())
        }
      }
      .onAppear {
        // 记录初始视口尺寸
        self.viewportSize = geometry.size
      }
      .onChange(of: url) { _, newURL in
        // 优先立即显示缓存内容（不清空 UI，避免短暂 loading）
        if let cachedFull = ImageLoader.shared.cachedFullImage(for: newURL) {
          self.displayImage = cachedFull
          self.isShowingFull = true
        } else if let cachedThumb = ImageLoader.shared.cachedThumbnail(for: newURL) {
          self.displayImage = cachedThumb
        }
      }
      .onChange(of: geometry.size) { _, newSize in
        // 视口尺寸变化时更新
        self.viewportSize = newSize
      }
      .transition(
        .asymmetric(
          insertion: .opacity.animation(Motion.Anim.fast),
          removal: .identity
        )
      )
    }
    .task(id: taskKey) {
      // 取消上一轮加载
      loadTask?.cancel()

      // 重置状态，但先尝试使用缓存避免闪烁
      self.isShowingFull = false

      let currentURL = url
      // 在主线程上组织渐进加载，避免跨 actor 传递 NSImage 带来的 Swift 6 Sendable 警告
      let task = Task { @MainActor in
        // 缓存直读：若命中完整图或缩略图，立即显示
        if let cachedFull = ImageLoader.shared.cachedFullImage(for: currentURL) {
          self.displayImage = cachedFull
          self.isShowingFull = true
        } else if let cachedThumb = ImageLoader.shared.cachedThumbnail(for: currentURL) {
          self.displayImage = cachedThumb
        }

        // 取消并替换上一轮完整图加载任务
        fullLoadTask?.cancel()
        fullLoadTask = Task { @MainActor in
          if let full = await ImageLoader.shared.loadFullImage(for: currentURL), !Task.isCancelled {
            withAnimation(Motion.Anim.standard) {
              self.displayImage = full
              self.isShowingFull = true
            }
          }
        }

        let scale = NSScreen.main?.backingScaleFactor ?? 2.0
        // 目标：视口长边 * scale * 2.5，并给出上限
        let targetLongSidePixels = Int(min(
          DownsampleRequestConstants.maxLongSidePixels,
          max(viewportSize.width, viewportSize.height) * scale * 2.5
        ))

        // 若尚未显示完整图，尝试基于视口像素的下采样图，作为更清晰的过渡
        if !self.isShowingFull {

          if let ds = await ImageLoader.shared.loadDownsampledImage(
            for: currentURL,
            targetLongSidePixels: targetLongSidePixels
          ), !Task.isCancelled, !self.isShowingFull {
            withAnimation(Motion.Anim.medium) {
              self.displayImage = ds
            }
          }
        }

        // 如果仍然没有任何图像，再获取一个快速缩略图占位（使用内部下采样方案）
        if self.displayImage == nil {
          if let downsampled = await ImageLoader.shared.loadDownsampledImage(
            for: currentURL,
            targetLongSidePixels: targetLongSidePixels
          ), !Task.isCancelled, !self.isShowingFull {
            withAnimation(Motion.Anim.medium) {
              self.displayImage = downsampled
            }
          } else if let thumb = await ImageLoader.shared.loadThumbnail(for: currentURL), !Task.isCancelled, !self.isShowingFull {
            withAnimation(Motion.Anim.medium) {
              self.displayImage = thumb
            }
          }
        }
        // 等待完整图加载任务结束（被取消或成功覆盖）以便结构化生命周期
        _ = await fullLoadTask?.value
      }

      self.loadTask = task
      await task.value
    }
    .onDisappear {
      loadTask?.cancel()
      fullLoadTask?.cancel()
    }
  }
}

// MARK: - Helpers
extension AsyncZoomableImageContainer {
  /// 仅解析元数据以获取宽高比（width/height）。失败返回 nil。
  static func readImageAspect(from url: URL) async -> CGFloat? {
    await Task.detached(priority: .utility) {
      guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
        let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
        let w = props[kCGImagePropertyPixelWidth] as? CGFloat,
        let h = props[kCGImagePropertyPixelHeight] as? CGFloat,
        w > 0, h > 0
      else { return nil }
      return w / h
    }.value
  }
}
