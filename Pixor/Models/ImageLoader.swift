// Pixor/Models/ImageLoader.swift

import AppKit
import Foundation
import ImageIO
import CoreImage

/// 线程安全的图片加载器，负责协调内存缓存、元数据磁盘缓存和高保真图片加载
@MainActor
final class ImageLoader {
  static let shared = ImageLoader()

  // 内存缓存：在主线程上安全访问
  private let thumbnailCache = NSCache<NSString, NSImage>()
  private let fullImageCache = NSCache<NSURL, NSImage>()
  private var memoryPressureSource: DispatchSourceMemoryPressure?

  // 专用队列用于后台图片处理
  private let processingQueue = DispatchQueue(
    label: "com.soyotube.Picser.imageloader.processing",
    qos: .userInitiated,
    attributes: .concurrent
  )

  // 同步队列用于保护缓存操作的原子性
  private let cacheQueue = DispatchQueue(
    label: "com.soyotube.Picser.imageloader.cache",
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
  func cachedFullImage(for url: URL) -> NSImage? {
    return cacheQueue.sync {
      return fullImageCache.object(forKey: url as NSURL)
    }
  }

  /// 同步返回内存中已缓存的缩略图（若存在）
  func cachedThumbnail(for url: URL) -> NSImage? {
    return cacheQueue.sync {
      return thumbnailCache.object(forKey: url.absoluteString as NSString)
    }
  }

  /// 加载用于UI显示的缩略图 (Thumbnail)
  /// 这是UI列表的"生命线"，必须极速响应。
  func loadThumbnail(for url: URL) async -> NSImage? {
    // 首先检查缓存
    if let cached = cachedThumbnail(for: url) {
      return cached
    }

    // 尝试从元数据磁盘缓存中获取
    if let metadata = await DiskCache.shared.retrieve(forKey: url.path) {
      if let image = NSImage(data: metadata.thumbnailData) {
        // 安全地缓存到内存
        await setThumbnail(image, for: url)
        return image
      }
    }

    // 如果磁盘缓存不存在，则在后台创建它
    await createAndCacheMetadata(for: url)

    // 创建完成后，再次尝试从内存缓存中读取
    return cachedThumbnail(for: url)
  }

  /// 加载高保真"原始样貌"的完整图片
  func loadFullImage(for url: URL) async -> NSImage? {
    // 首先检查缓存
    if let cached = cachedFullImage(for: url) {
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
      // 将磁盘 IO 放到后台线程
      if let data = await readFileData(from: url) {
        image = NSImage(data: data)
      }
    } else {
      // 静态图：后台解码并应用 EXIF 方向
      if let cgImage = await decodeOrientedCGImage(from: url) {
        let size = NSSize(width: cgImage.width, height: cgImage.height)
        image = NSImage(cgImage: cgImage, size: size)
      }
    }

    if let finalImage = image {
      // 安全地缓存到内存
      await setFullImage(finalImage, for: url)
    }

    return image
  }

  /// 基于"视口像素预算"先行下采样的中间质量图（静态图适用；GIF 返回 nil）
  /// - Parameter targetLongSidePixels: 长边目标像素（例如 视口长边 * 屏幕scale * 2.5，且建议上限 3K~4K）
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
      processingQueue.async {
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

    // 安全地缓存到内存
    await setFullImage(nsImage, for: url)
    return nsImage
  }

  // MARK: - 缓存创建和辅助方法

  /// 线程安全地设置缩略图到缓存
  private func setThumbnail(_ image: NSImage, for url: URL) async {
    await MainActor.run {
      self.cacheQueue.async {
        let cacheKey = url.absoluteString as NSString
        self.thumbnailCache.setObject(image, forKey: cacheKey, cost: self.estimatedCost(of: image))
      }
    }
  }

  /// 线程安全地设置完整图片到缓存
  private func setFullImage(_ image: NSImage, for url: URL) async {
    await MainActor.run {
      self.cacheQueue.async {
        let cacheKey = url as NSURL
        self.fullImageCache.setObject(image, forKey: cacheKey, cost: self.estimatedCost(of: image))
      }
    }
  }

  /// 在后台为一张图片创建并存储其元数据缓存
  private func createAndCacheMetadata(for url: URL) async {
    // 1. 创建一个微缩略图 (例如 256x256)
    let thumbnailData = await withCheckedContinuation { continuation in
      processingQueue.async {
        let result = self.createThumbnailData(from: url, maxPixelSize: 256)
        continuation.resume(returning: result)
      }
    }

    guard let data = thumbnailData else {
      return
    }

    // 2. 使用缩略图数据和原始URL创建 MetadataCache 对象
    guard let metadata = MetadataCache(fromUrl: url, thumbnailData: data) else {
      return
    }

    // 3. 将新的元数据对象存入磁盘缓存
    await DiskCache.shared.store(metadata: metadata, forKey: url.path)

    // 4. 创建 NSImage 并安全地更新缓存
    if let image = NSImage(data: data) {
      await setThumbnail(image, for: url)
    }
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
    return await withCheckedContinuation { continuation in
      processingQueue.async {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else {
          continuation.resume(returning: nil)
          return
        }

        // 解码原始 CGImage
        let options: [CFString: Any] = [kCGImageSourceShouldCacheImmediately: true]
        guard let base = CGImageSourceCreateImageAtIndex(src, 0, options as CFDictionary) else {
          continuation.resume(returning: nil)
          return
        }

        // 读取 EXIF 方向（1..8），默认 1 表示无需旋转
        var exifOrientation: Int32 = 1
        if let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
           let num = props[kCGImagePropertyOrientation] as? NSNumber {
          exifOrientation = num.int32Value
        }
        if exifOrientation == 1 {
          continuation.resume(returning: base)
          return
        }

        // 使用 Core Image 应用方向矫正
        let ciImage = CIImage(cgImage: base)
        let oriented = ciImage.oriented(forExifOrientation: exifOrientation)
        let context = CIContext(options: nil)
        let result = context.createCGImage(oriented, from: oriented.extent)
        continuation.resume(returning: result)
      }
    }
  }

  /// 后台读取文件数据（用于 GIF 等需要直接构造 NSImage 的场景）
  private func readFileData(from url: URL) async -> Data? {
    return await withCheckedContinuation { continuation in
      processingQueue.async {
        // 使用内存映射降低拷贝开销
        let result = try? Data(contentsOf: url, options: .mappedIfSafe)
        continuation.resume(returning: result)
      }
    }
  }

  /// 估算 NSImage 的内存开销
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
      self.cacheQueue.async {
        self.thumbnailCache.removeAllObjects()
        self.fullImageCache.removeAllObjects()
      }
    }
    source.resume()
    self.memoryPressureSource = source
  }

  /// 清理所有内存缓存（线程安全）
  func clearAllCaches() {
    cacheQueue.async {
      self.thumbnailCache.removeAllObjects()
      self.fullImageCache.removeAllObjects()
    }
  }
}
