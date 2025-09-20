// Pixor/Models/ImageLoader.swift

import AppKit
import Foundation
import ImageIO
import CoreImage

/// 最终升级版 ImageLoader，负责协调内存缓存、元数据磁盘缓存和高保真图片加载。
final class ImageLoader: @unchecked Sendable {
  static let shared = ImageLoader()

  // 内存缓存：仍然用于存储已解码的 NSImage 对象，避免重复创建，速度最快。
  private let thumbnailCache = NSCache<NSString, NSImage>()
  private let fullImageCache = NSCache<NSURL, NSImage>()
  private var memoryPressureSource: DispatchSourceMemoryPressure?
  /// 专用高优先级队列，用于执行耗时的下采样避免 QoS 逆转。
  private let downsampleQueue = DispatchQueue(
    label: "com.soyotube.Pixor.imageloader.downsample",
    qos: .userInitiated
  )

  private init() {
    // 适度限制内存缓存
    thumbnailCache.countLimit = 200
    thumbnailCache.totalCostLimit = 128 * 1024 * 1024  // 128MB
    fullImageCache.countLimit = 50
    fullImageCache.totalCostLimit = 256 * 1024 * 1024  // 256MB

    // 监听系统内存压力并清理内存缓存
    setupMemoryPressureObserver()
  }

  // MARK: - 核心加载方法

  // MARK: - 缓存直读（避免闪烁用）
  /// 同步返回内存中已缓存的完整图（若存在）
  @MainActor
  func cachedFullImage(for url: URL) -> NSImage? {
    fullImageCache.object(forKey: url as NSURL)
  }

  /// 同步返回内存中已缓存的缩略图（若存在）
  @MainActor
  func cachedThumbnail(for url: URL) -> NSImage? {
    thumbnailCache.object(forKey: url.absoluteString as NSString)
  }

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

    // 首先获取元数据（若无则回退扩展名判断）
    let metadata = await DiskCache.shared.retrieve(forKey: url.path)

    var image: NSImage?

    // 根据元数据中的格式，执行差异化加载
    let isGIF: Bool = {
      if let fmt = metadata?.originalFormat { return fmt == .gif }
      return url.pathExtension.lowercased() == "gif"
    }()

    if isGIF {
      // 将磁盘 IO 放到后台线程，避免阻塞主线程；在主线程创建 NSImage 以保证线程安全
      if let data = await readFileData(from: url) {
        image = NSImage(data: data)
      }
    } else {
      // 静态图：后台解码并应用 EXIF 方向，再在主线程创建 NSImage
      if let cgImage = await decodeOrientedCGImage(from: url) {
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

  /// 基于“视口像素预算”先行下采样的中间质量图（静态图适用；GIF 返回 nil）
  /// - Parameter targetLongSidePixels: 长边目标像素（例如 视口长边 * 屏幕scale * 2.5，且建议上限 3K~4K）
  @MainActor
  func loadDownsampledImage(for url: URL, targetLongSidePixels: Int) async -> NSImage? {
    guard targetLongSidePixels > 0 else { return nil }

    // GIF 不做静态下采样，避免丢失动画
    let meta = await DiskCache.shared.retrieve(forKey: url.path)
    if meta?.originalFormat == .gif || url.pathExtension.lowercased() == "gif" {
      return nil
    }

    if Task.isCancelled { return nil }

    let maxPixelSize = max(64, targetLongSidePixels)

    // 后台生成带方向矫正的缩略 CGImage（高质量下采样）
    let cg: CGImage? = await withCheckedContinuation { continuation in
      downsampleQueue.async {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else {
          continuation.resume(returning: nil)
          return
        }
        let opts: [CFString: Any] = [
          kCGImageSourceCreateThumbnailFromImageIfAbsent: true,
          kCGImageSourceCreateThumbnailWithTransform: true,  // 应用 EXIF 方向
          kCGImageSourceShouldCacheImmediately: true,
          kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        let result = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary)
        continuation.resume(returning: result)
      }
    }

    guard let cgImage = cg else { return nil }

    if Task.isCancelled { return nil }

    let size = NSSize(width: cgImage.width, height: cgImage.height)
    let nsImage = NSImage(cgImage: cgImage, size: size)

    // 将下采样结果临时塞入 full 缓存，便于快速重用；后续真正 full 会覆盖
    fullImageCache.setObject(nsImage, forKey: url as NSURL, cost: estimatedCost(of: nsImage))
    return nsImage
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

  /// 后台安全地解码并按 EXIF 方向校正为 CGImage
  private func decodeOrientedCGImage(from url: URL) async -> CGImage? {
    await Task.detached(priority: .userInitiated) {
      guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }

      // 解码原始 CGImage
      let options: [CFString: Any] = [kCGImageSourceShouldCacheImmediately: true]
      guard let base = CGImageSourceCreateImageAtIndex(src, 0, options as CFDictionary) else {
        return nil
      }

      // 读取 EXIF 方向（1..8），默认 1 表示无需旋转
      var exifOrientation: Int32 = 1
      if let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
         let num = props[kCGImagePropertyOrientation] as? NSNumber {
        exifOrientation = num.int32Value
      }
      if exifOrientation == 1 { return base }

      // 使用 Core Image 应用方向矫正
      let ciImage = CIImage(cgImage: base)
      let oriented = ciImage.oriented(forExifOrientation: exifOrientation)
      let context = CIContext(options: nil)
      return context.createCGImage(oriented, from: oriented.extent)
    }.value
  }

  /// 后台读取文件数据（用于 GIF 等需要直接构造 NSImage 的场景）
  private func readFileData(from url: URL) async -> Data? {
    await Task.detached(priority: .userInitiated) {
      // 使用内存映射降低拷贝开销
      return try? Data(contentsOf: url, options: .mappedIfSafe)
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

  // MARK: - 内存压力处理
  private func setupMemoryPressureObserver() {
    let source = DispatchSource.makeMemoryPressureSource(eventMask: .all, queue: .global(qos: .utility))
    source.setEventHandler { [weak self] in
      guard let self else { return }
      self.thumbnailCache.removeAllObjects()
      self.fullImageCache.removeAllObjects()
    }
    source.resume()
    self.memoryPressureSource = source
  }
}
