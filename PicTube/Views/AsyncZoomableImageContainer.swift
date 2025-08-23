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

  @State private var previewImage: NSImage?
  @State private var viewportImage: NSImage?

  var body: some View {
    GeometryReader { geometry in
      ZStack {
        if let viewportImage {
          ZoomableImageView(image: viewportImage)
            .transition(.opacity)
        } else if let previewImage {
          // 预览阶段使用轻量 Image，避免初始化缩放/手势等开销
          Image(nsImage: previewImage)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .transition(.opacity)
            .allowsHitTesting(false)
        } else {
          Rectangle()
            .fill(Color.secondary.opacity(0.1))
            .overlay(ProgressView())
        }
      }
      .id(url)
      .task(id: url) {
        // 1) 先用 QuickLook 生成较清晰的预览（极快、低内存）
        let scale = NSScreen.main?.backingScaleFactor ?? 2.0
        let fitSide = max(geometry.size.width, geometry.size.height)
        let previewPoints = max(256.0, min(1024.0, fitSide))
        if previewImage == nil {
          if let cg = await ThumbnailService.generate(
            url: url,
            size: CGSize(width: previewPoints, height: previewPoints),
            scale: scale
          ) {
            previewImage = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
          } else {
            // 回退
            previewImage = await ImageLoader.shared.loadThumbnail(for: url)
          }
        }

        // 先尝试使用系统高质量缩略图作为 viewport 图，加速首切换
        if let cg = await ThumbnailService.generateHigh(
          url: url,
          size: CGSize(width: geometry.size.width, height: geometry.size.height),
          scale: scale
        ) {
          viewportImage = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
        } else {
          viewportImage = await ImageLoader.shared.loadFullImage(for: url)
        }

        // 稍作延时再进行较重的下采样解码，避免阻塞首帧
        try? await Task.sleep(nanoseconds: 30_000_000)  // 30ms
        if viewportImage == previewImage {
          viewportImage = await ImageLoader.shared.loadFullImage(for: url)
        }

        // 3) 完成后释放预览图，降低内存峰值
        if viewportImage != nil {
          previewImage = nil
        }
      }
    }
  }
}
