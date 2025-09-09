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
          ZoomableImageView(image: image)
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
          insertion: .opacity.animation(.easeInOut(duration: 0.1)),
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
            withAnimation(.easeInOut(duration: 0.15)) {
              self.displayImage = full
              self.isShowingFull = true
            }
          }
        }

        // 若未命中任何缓存，再获取一个快速缩略图占位（QuickLook 优先，失败回退自有缩略图）
        if self.displayImage == nil {
          let scale = NSScreen.main?.backingScaleFactor ?? 2.0
          // 根据视口尺寸自适应请求大小，并加上上/下界避免过大/过小
          let vw = max(256, min(viewportSize.width, 1600))
          let vh = max(256, min(viewportSize.height, 1600))
          let requestedSize = CGSize(width: vw, height: vh)

          if let cg = await ThumbnailService.generate(
            url: currentURL,
            size: requestedSize,
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
