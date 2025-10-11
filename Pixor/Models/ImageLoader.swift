// Pixor/Models/ImageLoader.swift

import AppKit
import Foundation
import ImageIO
import CoreImage

/// 优化的图片加载器，使用统一内存缓存和智能加载策略
@MainActor
final class ImageLoader {
  static let shared = ImageLoader()

  // 统一内存缓存：缓存所有尺寸的图片，统一管理
  private let imageCache = NSCache<NSString, NSImage>()
  private var memoryPressureSource: DispatchSourceMemoryPressure?

  // 后台处理队列
  private let processingQueue = DispatchQueue(
    label: "com.pixor.imageloader.processing",
    qos: .userInitiated,
    attributes: .concurrent
  )

  // 缓存同步队列
  private let cacheQueue = DispatchQueue(
    label: "com.pixor.imageloader.cache",
    qos: .userInitiated
  )

  private init() {
    // 简化内存配置：总共不超过64MB
    imageCache.countLimit = 100  // 总图片数量限制
    imageCache.totalCostLimit = 64 * 1024 * 1024  // 64MB总内存限制

    // 设置内存压力监听
    setupMemoryPressureObserver()
  }

  // MARK: - 核心加载方法

  // MARK: - 缓存访问

  /// 生成缓存键
  private func cacheKey(for url: URL, suffix: String = "") -> NSString {
    return (url.absoluteString + suffix) as NSString
  }

  /// 统一的缓存读取方法（线程安全）
  private func cachedImage(for url: URL, suffix: String = "") -> NSImage? {
    return cacheQueue.sync {
      self.imageCache.object(forKey: cacheKey(for: url, suffix: suffix))
    }
  }

  /// 统一的缓存设置方法（线程安全）
  private func setCachedImage(_ image: NSImage, for url: URL, suffix: String = "") async {
    let cost = estimatedCost(of: image)  // nonisolated 方法可以直接调用

    // 使用 MainActor.run 避免嵌套 Task，统一架构
    await MainActor.run {
      self.imageCache.setObject(image, forKey: cacheKey(for: url, suffix: suffix), cost: cost)
    }
  }

  /// 公开的缓存访问方法
  func cachedThumbnail(for url: URL) -> NSImage? {
    return cachedImage(for: url, suffix: "_thumb")
  }

  func cachedFullImage(for url: URL) -> NSImage? {
    return cachedImage(for: url)
  }

  /// 加载缩略图：优先内存缓存，其次磁盘缓存，最后重新生成
  func loadThumbnail(for url: URL) async -> NSImage? {
    // 1. 检查内存缓存
    if let cached = cachedThumbnail(for: url) {
      return cached
    }

    // 2. 尝试从磁盘缓存快速加载
    if let metadata = await DiskCache.shared.retrieve(forKey: url.path),
       let image = NSImage(data: metadata.thumbnailData) {
      await setCachedImage(image, for: url, suffix: "_thumb")
      return image
    }

    // 3. 重新生成缩略图
    return await generateThumbnail(for: url)
  }

  /// 生成缩略图并缓存（优化版本）
  private func generateThumbnail(for url: URL) async -> NSImage? {
    // 1. 在后台队列生成缩略图数据
    let thumbnailData = await Task.detached(priority: .userInitiated) {
      self.createThumbnailData(from: url, maxPixelSize: 256)
    }.value

    guard let data = thumbnailData else { return nil }

    // 2. 创建缩略图
    guard let image = NSImage(data: data) else { return nil }

    // 3. 缓存到内存
    await setCachedImage(image, for: url, suffix: "_thumb")

    // 4. 异步缓存到磁盘（不阻塞当前操作）
    Task.detached(priority: .background) {
      await self.createAndCacheMetadata(for: url)
    }

    return image
  }

  /// 加载完整图片：智能加载并缓存
  func loadFullImage(for url: URL) async -> NSImage? {
    // 1. 检查内存缓存
    if let cached = cachedFullImage(for: url) {
      return cached
    }

    // 2. 根据格式智能加载
    let image = await loadImageByFormat(for: url)

    // 3. 缓存结果
    if let finalImage = image {
      await setCachedImage(finalImage, for: url)
    }

    return image
  }

  /// 根据图片格式进行差异化加载
  private func loadImageByFormat(for url: URL) async -> NSImage? {
    // GIF处理
    if url.pathExtension.lowercased() == "gif" {
      if let data = await readFileData(from: url) {
        return NSImage(data: data)
      }
    }

    // 静态图处理：EXIF方向矫正
    if let cgImage = await decodeOrientedCGImage(from: url) {
      let size = NSSize(width: cgImage.width, height: cgImage.height)
      return NSImage(cgImage: cgImage, size: size)
    }

    return nil
  }

  /// 智能加载适配尺寸的图片
  /// 自动选择最佳尺寸：缩略图、下采样图或完整图
  func loadOptimizedImage(for url: URL, targetLongSidePixels: Int) async -> NSImage? {
    guard targetLongSidePixels > 0 else { return nil }

    // GIF 直接返回完整图
    if url.pathExtension.lowercased() == "gif" {
      return await loadFullImage(for: url)
    }

    // 小尺寸：使用缩略图
    if targetLongSidePixels <= 256 {
      return await loadThumbnail(for: url)
    }

    // 中等尺寸：生成下采样图
    return await generateDownsampledImage(for: url, targetLongSidePixels: targetLongSidePixels)
  }

  /// 生成下采样图片
  private func generateDownsampledImage(for url: URL, targetLongSidePixels: Int) async -> NSImage? {
    // let cacheKey = url.absoluteString + "_down_\(targetLongSidePixels)"

    // 检查缓存
    if let cached = cachedImage(for: url, suffix: "_down_\(targetLongSidePixels)") {
      return cached
    }

    // 生成下采样图
    let maxPixelSize = max(256, min(targetLongSidePixels, 2048))  // 限制最大尺寸

    return await withCheckedContinuation { continuation in
      processingQueue.async {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cgImage = CGImageSourceCreateThumbnailAtIndex(src, 0, [
                kCGImageSourceCreateThumbnailFromImageIfAbsent: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: true,
                kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
              ] as CFDictionary) else {
          continuation.resume(returning: nil)
          return
        }

        let size = NSSize(width: cgImage.width, height: cgImage.height)
        let nsImage = NSImage(cgImage: cgImage, size: size)

        // 缓存结果
        Task {
          await self.setCachedImage(nsImage, for: url, suffix: "_down_\(targetLongSidePixels)")
        }

        continuation.resume(returning: nsImage)
      }
    }
  }

  // MARK: - 磁盘缓存管理

  /// 创建并存储图片元数据到磁盘缓存
  private func createAndCacheMetadata(for url: URL) async {
    let thumbnailData = await withCheckedContinuation { continuation in
      processingQueue.async {
        continuation.resume(returning: self.createThumbnailData(from: url, maxPixelSize: 256))
      }
    }

    guard let data = thumbnailData,
          let metadata = MetadataCache(fromUrl: url, thumbnailData: data) else {
      return
    }

    // 异步存储到磁盘，不阻塞当前操作
    Task {
      await DiskCache.shared.store(metadata: metadata, forKey: url.path)
    }
  }

  /// 从原始图片文件创建一个小尺寸、高压缩率的缩略图二进制数据 (Data)
  nonisolated private func createThumbnailData(from url: URL, maxPixelSize: Int) -> Data? {
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

  /// 估算 NSImage 的内存开销（nonisolated 避免 actor 隔离）
  nonisolated private func estimatedCost(of image: NSImage) -> Int {
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

  // MARK: - 内存管理

  /// 设置内存压力监听
  private func setupMemoryPressureObserver() {
    let source = DispatchSource.makeMemoryPressureSource(eventMask: .all, queue: .global(qos: .utility))
    source.setEventHandler { [weak self] in
      guard let self else { return }
      Task { @MainActor in
        self.imageCache.removeAllObjects()
      }
    }
    source.resume()
    self.memoryPressureSource = source
  }

  /// 清理所有内存缓存
  func clearAllCaches() {
    Task { @MainActor in
      self.imageCache.removeAllObjects()
    }
  }
}
