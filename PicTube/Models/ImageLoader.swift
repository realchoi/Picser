// PicTube/Models/ImageLoader.swift

import AppKit
import Foundation
import ImageIO

/// 最终升级版 ImageLoader，负责协调内存缓存、元数据磁盘缓存和高保真图片加载。
final class ImageLoader: @unchecked Sendable {
  static let shared = ImageLoader()

  // 内存缓存：仍然用于存储已解码的 NSImage 对象，避免重复创建，速度最快。
  private let thumbnailCache = NSCache<NSString, NSImage>()
  private let fullImageCache = NSCache<NSURL, NSImage>()

  private let ioQueue = DispatchQueue(label: "image.loader.queue", qos: .userInitiated)

  private init() {
    // 适度限制内存缓存
    thumbnailCache.countLimit = 200
    thumbnailCache.totalCostLimit = 128 * 1024 * 1024  // 128MB
    fullImageCache.countLimit = 50
    fullImageCache.totalCostLimit = 256 * 1024 * 1024  // 256MB
  }

  // MARK: - 核心加载方法

  /// 加载用于UI显示的缩略图 (Thumbnail)
  /// 这是UI列表的“生命线”，必须极速响应。
  @MainActor
  func loadThumbnail(for url: URL) async -> NSImage? {
    let cacheKey = url.absoluteString as NSString
    if let cached = thumbnailCache.object(forKey: cacheKey) {
      return cached
    }

    // 尝试从元数据磁盘缓存中获取
    if let metadata = await DiskCache.shared.retrieve(forKey: url.path) {
      if let image = NSImage(data: metadata.thumbnailData) {
        self.thumbnailCache.setObject(image, forKey: cacheKey, cost: self.estimatedCost(of: image))
        return image
      }
    }

    // 如果磁盘缓存不存在，则在后台创建它。
    await createAndCacheMetadata(for: url)

    // 创建完成后，再次尝试从内存缓存中读取，这次应该会成功。
    return thumbnailCache.object(forKey: cacheKey)
  }

  /// 加载高保真“原始样貌”的完整图片
  @MainActor
  func loadFullImage(for url: URL) async -> NSImage? {
    let cacheKey = url as NSURL
    if let cached = fullImageCache.object(forKey: cacheKey) {
      return cached
    }

    // 首先获取元数据，它将告诉我们如何加载这张图片
    let metadata = await DiskCache.shared.retrieve(forKey: url.path)

    var image: NSImage?

    // 根据元数据中的格式，执行差异化加载
    if metadata?.originalFormat == .gif {
      // 对于 GIF，直接从原始 URL 加载，以保留动画！
      image = NSImage(contentsOf: url)
    } else {
      // 对于所有其他静态图片，我们先在后台安全地解码出 CGImage
      if let cgImage = await decodeCGImage(from: url) {
        // 然后在主线程 (@MainActor) 上安全地创建 NSImage
        let size = NSSize(width: cgImage.width, height: cgImage.height)
        image = NSImage(cgImage: cgImage, size: size)
      }
    }

    if let finalImage = image {
      self.fullImageCache.setObject(
        finalImage, forKey: cacheKey, cost: self.estimatedCost(of: finalImage))
    }

    return image
  }

  // MARK: - 缓存创建和辅助方法

  /// 在后台为一张图片创建并存储其元数据缓存。
  private func createAndCacheMetadata(for url: URL) async {
    // 在后台线程执行所有耗时操作
    await Task.detached(priority: .userInitiated) {
      // 1. 创建一个微缩略图 (例如 256x256)
      guard let thumbnailData = self.createThumbnailData(from: url, maxPixelSize: 256) else {
        return
      }

      // 2. 使用缩略图数据和原始URL创建 MetadataCache 对象
      guard let metadata = MetadataCache(fromUrl: url, thumbnailData: thumbnailData) else {
        return
      }

      // 3. 将新的元数据对象存入磁盘缓存
      await DiskCache.shared.store(metadata: metadata, forKey: url.path)

      // 4. 将线程安全的 thumbnailData 发送到主线程，并在主线程上创建 NSImage 并更新缓存
      await MainActor.run {
        if let image = NSImage(data: thumbnailData) {
          self.thumbnailCache.setObject(
            image, forKey: url.absoluteString as NSString, cost: self.estimatedCost(of: image))
        }
      }
    }.value
  }

  /// 从原始图片文件创建一个小尺寸、高压缩率的缩略图二进制数据 (Data)
  private func createThumbnailData(from url: URL, maxPixelSize: Int) -> Data? {
    guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }

    let options: [CFString: Any] = [
      kCGImageSourceCreateThumbnailFromImageIfAbsent: true,
      kCGImageSourceCreateThumbnailWithTransform: true,
      kCGImageSourceShouldCacheImmediately: true,
      kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
    ]

    guard let cgImage = CGImageSourceCreateThumbnailAtIndex(src, 0, options as CFDictionary) else {
      return nil
    }

    // 将缩略图编码为 JPG 格式，因为它是用于快速预览，体积小是关键
    let bitmapRep = NSBitmapImageRep(cgImage: cgImage)
    return bitmapRep.representation(using: .jpeg, properties: [.compressionFactor: 0.7])  // 70% 压缩率
  }

  /// 后台安全地将图片文件解码为 CGImage (CGImage 是线程安全的 Sendable 类型)
  private func decodeCGImage(from url: URL) async -> CGImage? {
    await Task.detached(priority: .userInitiated) {
      guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else {
        return nil
      }
      // 只解码，不创建 NSImage
      return CGImageSourceCreateImageAtIndex(src, 0, nil)
    }.value
  }

  // 估算 NSImage 的内存开销
  private func estimatedCost(of image: NSImage) -> Int {
    let pixels = Int(image.size.width * image.size.height)
    return pixels * 4  // 假设每个像素4字节 (RGBA)
  }

  /// 预取功能，现在是创建元数据缓存
  func prefetch(urls: [URL]) {
    Task.detached(priority: .background) {
      for url in urls {
        // 如果缓存已存在，则跳过
        if await DiskCache.shared.retrieve(forKey: url.path) == nil {
          // 这里我们忽略 createAndCacheMetadata 的返回值，因为它现在是 Void
          await self.createAndCacheMetadata(for: url)
        }
      }
    }
  }
}
