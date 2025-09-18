//
//  ThumbnailImageView.swift
//  Pixo
//
//  Created by Eric Cai on 2025/8/21.
//

import AppKit
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
          .animation(Motion.Anim.standard, value: image)
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
      let thumb = await ImageLoader.shared.loadThumbnail(for: url)
      await MainActor.run {
        self.image = thumb
      }
    }
    .onDisappear {
      // 行离屏后释放缩略图，避免持久占用内存
      self.image = nil
    }
  }
}
