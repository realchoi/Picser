//
//  ThumbnailImageView.swift
//  PicTube
//
//  Created by Eric Cai on 2025/8/21.
//

import AppKit
import QuickLookThumbnailing
import SwiftUI

/// 异步加载并显示缩略图，避免阻塞主线程
struct ThumbnailImageView: View {
  let url: URL
  let height: CGFloat

  @State private var image: NSImage?

  var body: some View {
    ZStack {
      if let image {
        Image(nsImage: image)
          .resizable()
          .aspectRatio(contentMode: .fill)
          .frame(height: height)
          .clipped()
          .transition(.opacity.combined(with: .scale))
      } else {
        // 占位符，保证列表滚动流畅
        Rectangle()
          .fill(Color.secondary.opacity(0.15))
          .frame(height: height)
          .overlay(
            ProgressView()
              .controlSize(.small)
          )
      }
    }
    .task(id: url) {
      // 优先使用 QuickLook 生成高效缩略图
      let scale = NSScreen.main?.backingScaleFactor ?? 2.0
      if let cg = await ThumbnailService.generate(
        url: url, size: CGSize(width: height, height: height), scale: scale)
      {
        let img = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
        self.image = img
      } else {
        // 回退到自有解码
        self.image = await ImageLoader.shared.loadThumbnail(for: url)
      }
    }
    .onDisappear {
      // 行离屏后释放缩略图，避免持久占用内存
      self.image = nil
    }
  }
}
