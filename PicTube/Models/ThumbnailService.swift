//
//  ThumbnailService.swift
//  PicTube
//
//  Created by Eric Cai on 2025/8/21.
//

import AppKit
import Foundation
import QuickLookThumbnailing

private let qlSemaphore = AsyncSemaphore(limit: 2)

/// 使用 QuickLookThumbnailing 生成缩略图（后台返回 CGImage，UI 侧再转 NSImage）
enum ThumbnailService {
  /// 低质量缩略图（points 尺寸，传入 scale）
  static func generate(url: URL, size: CGSize, scale: CGFloat) async -> CGImage? {
    await qlSemaphore.acquire()
    defer { Task { await qlSemaphore.release() } }
    return await withCheckedContinuation { continuation in
      let request = QLThumbnailGenerator.Request(
        fileAt: url,
        size: size,
        scale: scale,
        representationTypes: .lowQualityThumbnail
      )
      QLThumbnailGenerator.shared.generateRepresentations(for: request) { rep, _, _ in
        if let rep {
          continuation.resume(returning: rep.cgImage)
        } else {
          continuation.resume(returning: nil)
        }
      }
    }
  }

  /// 较高质量缩略图（适合视口首帧）
  static func generateHigh(url: URL, size: CGSize, scale: CGFloat) async -> CGImage? {
    await qlSemaphore.acquire()
    defer { Task { await qlSemaphore.release() } }
    return await withCheckedContinuation { continuation in
      let request = QLThumbnailGenerator.Request(
        fileAt: url,
        size: size,
        scale: scale,
        representationTypes: .thumbnail
      )
      QLThumbnailGenerator.shared.generateRepresentations(for: request) { rep, _, _ in
        if let rep {
          continuation.resume(returning: rep.cgImage)
        } else {
          continuation.resume(returning: nil)
        }
      }
    }
  }

  /// 预取一组缩略图（丢弃结果以加热系统缓存）
  static func prefetch(urls: [URL], size: CGSize, scale: CGFloat) {
    guard !urls.isEmpty else { return }
    for url in urls {
      let request = QLThumbnailGenerator.Request(
        fileAt: url,
        size: size,
        scale: scale,
        representationTypes: .lowQualityThumbnail
      )
      QLThumbnailGenerator.shared.generateRepresentations(for: request) { _, _, _ in
        // no-op; 系统会缓存
      }
    }
  }
}
