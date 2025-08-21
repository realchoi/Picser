//
//  ImageLoader.swift
//  PicTube
//
//  Created by Eric Cai on 2025/8/21.
//

import AppKit
import Foundation
import ImageIO

/// 负责异步解码图片与内存缓存，避免在主线程阻塞
final class ImageLoader: @unchecked Sendable {
  static let shared = ImageLoader()

  private let fullImageCache = NSCache<NSURL, NSImage>()
  private let thumbnailCache = NSCache<NSString, NSImage>()
  private let downsampleCache = NSCache<NSString, NSImage>()
  private let ioQueue = DispatchQueue(label: "image.loader.queue", qos: .userInitiated)

  private init() {
    // 适度限制缓存，防止占用过多内存（按需可调）
    fullImageCache.countLimit = 50
    thumbnailCache.countLimit = 200
    downsampleCache.countLimit = 150
    // 估算内存上限（字节）。整体降低阈值
    fullImageCache.totalCostLimit = 256 * 1024 * 1024
    thumbnailCache.totalCostLimit = 128 * 1024 * 1024
    downsampleCache.totalCostLimit = 256 * 1024 * 1024

    Task {
      let dir = await DiskCache.shared.cacheDirectoryURL()
      print("DiskCache directory:", dir.path)
    }
  }

  /// 异步加载缩略图，返回已解码的 NSImage
  @MainActor
  func loadThumbnail(for url: URL, maxPixel: Int) async -> NSImage? {
    let cacheKey = thumbnailKey(url: url, maxPixel: maxPixel)
    if let cached = thumbnailCache.object(forKey: cacheKey as NSString) {
      return cached
    }
    // 磁盘缓存
    if let diskURL = await DiskCache.shared.retrieve(forKey: cacheKey),
      let disk = NSImage(contentsOf: diskURL)
    {
      thumbnailCache.setObject(disk, forKey: cacheKey as NSString, cost: estimatedCost(of: disk))
      return disk
    }

    return await withCheckedContinuation { continuation in
      ioQueue.async { [weak self] in
        guard let self else {
          continuation.resume(returning: nil)
          return
        }
        let image = self.decodeImage(url: url, maxPixel: maxPixel)
        if let image {
          self.thumbnailCache.setObject(
            image, forKey: cacheKey as NSString, cost: self.estimatedCost(of: image))
          Task { await DiskCache.shared.store(image: image, forKey: cacheKey) }
        }
        continuation.resume(returning: image)
      }
    }
  }

  /// 异步加载原图（或限制最大像素避免超大图占用），返回已解码的 NSImage
  @MainActor
  func loadFullImage(for url: URL, maxPixel: Int? = nil) async -> NSImage? {
    if maxPixel == nil, let cached = fullImageCache.object(forKey: url as NSURL) {
      return cached
    }
    if let maxPixel,
      let cachedDown = downsampleCache.object(
        forKey: downsampleKey(url: url, maxPixel: maxPixel) as NSString)
    {
      return cachedDown
    }
    // 磁盘缓存
    if let maxPixel,
      let diskURL = await DiskCache.shared.retrieve(
        forKey: downsampleKey(url: url, maxPixel: maxPixel)),
      let disk = NSImage(contentsOf: diskURL)
    {
      downsampleCache.setObject(
        disk, forKey: downsampleKey(url: url, maxPixel: maxPixel) as NSString,
        cost: estimatedCost(of: disk))
      return disk
    } else if maxPixel == nil,
      let diskURL = await DiskCache.shared.retrieve(forKey: url.absoluteString),
      let disk = NSImage(contentsOf: diskURL)
    {
      fullImageCache.setObject(disk, forKey: url as NSURL, cost: estimatedCost(of: disk))
      return disk
    }

    return await withCheckedContinuation { continuation in
      ioQueue.async { [weak self] in
        guard let self else {
          continuation.resume(returning: nil)
          return
        }
        let image = self.decodeImage(url: url, maxPixel: maxPixel)
        if let image {
          if let maxPixel {
            self.downsampleCache.setObject(
              image, forKey: self.downsampleKey(url: url, maxPixel: maxPixel) as NSString,
              cost: self.estimatedCost(of: image))
            Task {
              await DiskCache.shared.store(
                image: image, forKey: self.downsampleKey(url: url, maxPixel: maxPixel))
            }
          } else {
            self.fullImageCache.setObject(
              image, forKey: url as NSURL, cost: self.estimatedCost(of: image))
            Task { await DiskCache.shared.store(image: image, forKey: url.absoluteString) }
          }
        }
        continuation.resume(returning: image)
      }
    }
  }

  /// 预取一组图片，静默放入缓存
  func prefetch(urls: [URL], maxPixel: Int? = nil) {
    guard !urls.isEmpty else { return }
    ioQueue.async { [weak self] in
      guard let self else { return }
      for url in urls {
        // 已缓存直接跳过
        if maxPixel == nil, self.fullImageCache.object(forKey: url as NSURL) != nil { continue }
        _ = self.decodeImage(url: url, maxPixel: maxPixel)
      }
    }
  }

  /// 根据当前缓存压力做一次裁剪（可在切换后调用）
  func trimMemoryAfterSelection() {
    // NSCache 无显式 trim 接口，这里通过降低 limit 触发回收，再恢复
    let oldFull = fullImageCache.totalCostLimit
    let oldDown = downsampleCache.totalCostLimit
    let oldThumb = thumbnailCache.totalCostLimit
    fullImageCache.totalCostLimit = max(oldFull / 2, 64 * 1024 * 1024)
    downsampleCache.totalCostLimit = max(oldDown / 2, 64 * 1024 * 1024)
    thumbnailCache.totalCostLimit = max(oldThumb / 2, 32 * 1024 * 1024)
    // 恢复到原值，保留系统已回收的部分
    fullImageCache.totalCostLimit = oldFull
    downsampleCache.totalCostLimit = oldDown
    thumbnailCache.totalCostLimit = oldThumb
  }

  // MARK: - Private helpers

  private func thumbnailKey(url: URL, maxPixel: Int) -> String {
    return url.absoluteString + "|thumb|" + String(maxPixel)
  }

  private func downsampleKey(url: URL, maxPixel: Int) -> String {
    return url.absoluteString + "|down|" + String(maxPixel)
  }

  /// 使用 ImageIO 解码（支持限制最大像素，避免超大图开销）
  private func decodeImage(url: URL, maxPixel: Int?) -> NSImage? {
    guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }

    // 如果指定 maxPixel，使用缩略图解码；否则解码完整图像
    if let maxPixel {
      let options: [CFString: Any] = [
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        kCGImageSourceCreateThumbnailWithTransform: true,
        kCGImageSourceShouldCache: true,
      ]
      if let cgThumb = CGImageSourceCreateThumbnailAtIndex(src, 0, options as CFDictionary) {
        return nsImage(from: cgThumb)
      }
      return nil
    } else {
      let options: [CFString: Any] = [
        kCGImageSourceShouldCache: true,
        kCGImageSourceShouldCacheImmediately: true,
      ]
      if let cg = CGImageSourceCreateImageAtIndex(src, 0, options as CFDictionary) {
        return nsImage(from: cg)
      }
      return nil
    }
  }

  private func nsImage(from cgImage: CGImage) -> NSImage {
    // 直接使用 NSImage(cgImage:size:)，避免在后台线程使用图形上下文
    let size = NSSize(width: cgImage.width, height: cgImage.height)
    return NSImage(cgImage: cgImage, size: size)
  }

  private func estimatedCost(of image: NSImage) -> Int {
    // 估算像素数 * 4 字节，注意 NSImage.size 单位是 points；我们在构造时使用像素尺寸
    let pixels = Int(max(image.size.width, 1) * max(image.size.height, 1))
    return min(pixels * 4, Int(Int32.max))
  }
}
