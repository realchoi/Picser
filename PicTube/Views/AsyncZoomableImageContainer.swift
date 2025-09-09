//
//  AsyncZoomableImageContainer.swift
//  PicTube
//
//  Created by Eric Cai on 2025/8/21.
//

import AppKit
import QuickLookThumbnailing
import SwiftUI

/// 渐进式加载主图：先显示快速缩略图，再无缝切换到全尺寸已解码图像
struct AsyncZoomableImageContainer: View {
  let url: URL

  // 我们现在只需要一个 State 来存储最终显示的图片
  @State private var displayImage: NSImage?
  @State private var isShowingFull: Bool = false
  @State private var loadTask: Task<Void, Never>?
  @State private var fullLoadTask: Task<Void, Never>?

  var body: some View {
    ZStack {
      if let image = displayImage {
        ZoomableImageView(image: image)
      } else {
        // 保持加载中的占位符
        Rectangle()
          .fill(Color.secondary.opacity(0.1))
          .overlay(ProgressView())
      }
    }
    .transition(
      .asymmetric(insertion: .opacity.animation(.easeInOut(duration: 0.1)), removal: .identity)
    )
    .task(id: url) {
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
        } else {
          self.displayImage = nil
        }

        // 取消并替换上一轮完整图加载任务
        fullLoadTask?.cancel()
        fullLoadTask = Task { @MainActor in
          if let full = await ImageLoader.shared.loadFullImage(for: currentURL), !Task.isCancelled {
            withAnimation(.easeInOut(duration: 0.15)) {
              self.displayImage = full
              self.isShowingFull = true
            }
          }
        }

        // 若未命中任何缓存，再获取一个快速缩略图占位（QuickLook 优先，失败回退自有缩略图）
        if self.displayImage == nil {
          let scale = NSScreen.main?.backingScaleFactor ?? 2.0
          if let cg = await ThumbnailService.generate(
            url: currentURL,
            size: CGSize(width: 256, height: 256),
            scale: scale
          ) {
            if !isShowingFull {
              self.displayImage = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
            }
          } else if let thumb = await ImageLoader.shared.loadThumbnail(for: currentURL) {
            if !isShowingFull {
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
