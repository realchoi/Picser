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
    .id(url)
    .transition(
      .asymmetric(insertion: .opacity.animation(.easeInOut(duration: 0.1)), removal: .identity)
    )
    .task(id: url) {
      // 【核心改造】
      // 重置状态，准备加载新图片
      self.displayImage = nil

      // 直接调用我们强大的 ImageLoader 来加载最终的图片。
      // ImageLoader 内部已经处理了 GIF 和其他静态图片的差异化加载。
      // 这样就绕过了 ThumbnailService 只能生成静态图的问题。
      self.displayImage = await ImageLoader.shared.loadFullImage(for: url)
    }
  }
}
