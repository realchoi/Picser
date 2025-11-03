//
//  AsyncZoomableImageContainer.swift
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
  var isSlideshowActive: Bool = false

  // 我们现在只需要一个 State 来存储最终显示的图片
  @State private var displayImage: NSImage?
  @State private var displayedImageURL: URL?
  @State private var isShowingFull: Bool = false
  @State private var loadTask: Task<Void, Never>?
  @State private var fullLoadTask: Task<Void, Never>?
  @State private var viewportSize: CGSize = .zero
  @State private var backingScaleFactor: CGFloat = NSScreen.main?.backingScaleFactor ?? 2.0

  private var isSeamlessModeEnabled: Bool { isSlideshowActive }

  // 任务触发键：由 URL 和视口的离散尺寸组成，满足 Equatable
  private var taskKey: String {
    let w = Int(viewportSize.width.rounded())
    let h = Int(viewportSize.height.rounded())
    let scaleKey = Int((backingScaleFactor * 1000).rounded())
    return url.absoluteString + "|" + String(w) + "x" + String(h) + "|s\(scaleKey)"
  }

  var body: some View {
    GeometryReader { geometry in
      ZStack {
        if let image = displayImage {
          ZoomableImageView(
            image: image,
            transform: transform,
            windowToken: windowToken,
            sourceURL: displayedImageURL ?? url,
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
        Task { @MainActor in
          updateBackingScaleFactor()
        }
      }
      .onChange(of: url) { _, newURL in
        // 切换图片时显示 Loading，除非立即有缓存
        if let cachedFull = ImageLoader.shared.cachedFullImage(for: newURL) {
          showImage(cachedFull, for: newURL)
          self.isShowingFull = true
        } else if let cachedThumb = ImageLoader.shared.cachedThumbnail(for: newURL) {
          showImage(cachedThumb, for: newURL)
          self.isShowingFull = false
        } else {
          self.isShowingFull = false
          if !isSeamlessModeEnabled || displayImage == nil {
            showImage(nil, for: nil)
          }
        }
      }
      .onChange(of: geometry.size) { _, newSize in
        // 视口尺寸变化时更新
        self.viewportSize = newSize
      }
      .onChange(of: isSlideshowActive) { _, newValue in
        guard !newValue else { return }
        guard displayedImageURL != url else { return }
        if let cachedFull = ImageLoader.shared.cachedFullImage(for: url) {
          showImage(cachedFull, for: url)
          self.isShowingFull = true
        } else if let cachedThumb = ImageLoader.shared.cachedThumbnail(for: url) {
          showImage(cachedThumb, for: url)
          self.isShowingFull = false
        } else {
          showImage(nil, for: nil)
          self.isShowingFull = false
        }
      }
    }
    .task(id: taskKey) {
      // 取消上一轮加载
      loadTask?.cancel()
      fullLoadTask?.cancel()
      fullLoadTask = nil

      // 重置状态，但先尝试使用缓存避免闪烁
      self.isShowingFull = false

      let currentURL = url
      // 在主线程上组织渐进加载，避免跨 actor 传递 NSImage 带来的 Swift 6 Sendable 警告
      let task = Task { @MainActor in
        updateBackingScaleFactor()
        // 第1步：缓存直读，立即显示缓存内容（避免闪烁）
        if let cachedFull = ImageLoader.shared.cachedFullImage(for: currentURL) {
          showImage(cachedFull, for: currentURL)
          self.isShowingFull = true
        } else if let cachedThumb = ImageLoader.shared.cachedThumbnail(for: currentURL) {
          showImage(cachedThumb, for: currentURL)
        }

        let scale = backingScaleFactor
        // 目标：视口长边 * scale * 2.5，并给出上限
        let targetLongSidePixels = Int(min(
          DownsampleRequestConstants.maxLongSidePixels,
          max(viewportSize.width, viewportSize.height) * scale * 2.5
        ))

        var showingCurrent = (self.displayedImageURL == currentURL)

        // 第2步：如果还没有完整图，先加载缩略图
        if !showingCurrent && !self.isShowingFull {
          if let thumb = await ImageLoader.shared.loadThumbnail(for: currentURL), !Task.isCancelled {
            showImage(thumb, for: currentURL)
            showingCurrent = (self.displayedImageURL == currentURL)
          }
        }

        // 第3步：加载优化的中等尺寸图片（更好的过渡）
        if !self.isShowingFull && !Task.isCancelled {
          if let optimized = await ImageLoader.shared.loadOptimizedImage(
            for: currentURL,
            targetLongSidePixels: targetLongSidePixels
          ), !Task.isCancelled, !self.isShowingFull {
            showImage(optimized, for: currentURL)
            showingCurrent = (self.displayedImageURL == currentURL)
          }
        }

        // 第4步：最终加载完整图片
        fullLoadTask?.cancel()
        fullLoadTask = Task { @MainActor in
          if let full = await ImageLoader.shared.loadFullImage(for: currentURL), !Task.isCancelled {
            showImage(full, for: currentURL)
            self.isShowingFull = true
          }
        }

        // 等待完整图加载任务结束
        _ = await fullLoadTask?.value
      }

      self.loadTask = task
      await task.value
    }
    .onDisappear {
      loadTask?.cancel()
      fullLoadTask?.cancel()
    }
    .onReceive(NotificationCenter.default.publisher(for: NSWindow.didChangeBackingPropertiesNotification)) { notif in
      handleWindowScaleNotification(notif)
    }
    .onReceive(NotificationCenter.default.publisher(for: NSWindow.didChangeScreenNotification)) { notif in
      handleWindowScaleNotification(notif)
    }
  }
}

// MARK: - Helpers
extension AsyncZoomableImageContainer {
  @MainActor
  private func updateBackingScaleFactor() {
    let resolved = Self.resolveBackingScaleFactor(for: windowToken)
    if abs(resolved - backingScaleFactor) > 0.01 {
      backingScaleFactor = resolved
    }
  }

  @MainActor
  private static func resolveBackingScaleFactor(for token: UUID) -> CGFloat {
    if let window = KeyboardShortcutManager.shared.window(for: token) {
      if let screen = window.screen {
        return screen.backingScaleFactor
      }
      return window.backingScaleFactor
    }

    if let keyWindow = NSApp.keyWindow {
      return keyWindow.screen?.backingScaleFactor ?? keyWindow.backingScaleFactor
    }

    if let mainWindow = NSApp.mainWindow {
      return mainWindow.screen?.backingScaleFactor ?? mainWindow.backingScaleFactor
    }

    if let screen = NSScreen.main {
      return screen.backingScaleFactor
    }

    return 2.0
  }

  private func handleWindowScaleNotification(_ notif: Notification) {
    guard let window = notif.object as? NSWindow else { return }
    Task { @MainActor in
      guard let tracked = KeyboardShortcutManager.shared.window(for: windowToken), tracked === window else { return }
      updateBackingScaleFactor()
    }
  }

  /// 统一更新当前显示的图片与其来源 URL，便于与异步加载管线同步。
  @MainActor
  private func showImage(_ image: NSImage?, for sourceURL: URL?) {
    displayImage = image
    displayedImageURL = sourceURL
  }

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
