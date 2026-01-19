// ImageLoader.swift

import AppKit
import Foundation
import ImageIO
import CoreImage

// 并发限流器：用于控制同时进行的异步任务数量
private actor ConcurrencyLimiter {
  private let maxConcurrent: Int
  private var current: Int = 0
  private var waiters: [CheckedContinuation<Void, Never>] = []

  init(maxConcurrent: Int) {
    self.maxConcurrent = max(1, maxConcurrent)
  }

  func acquire() async {
    if current < maxConcurrent {
      current += 1
      return
    }
    await withCheckedContinuation { continuation in
      waiters.append(continuation)
    }
  }

  func release() {
    if waiters.isEmpty {
      current = max(0, current - 1)
      return
    }
    let continuation = waiters.removeFirst()
    continuation.resume()
  }
}

/// 优化的图片加载器，使用统一内存缓存和智能加载策略
@MainActor
final class ImageLoader {
  static let shared = ImageLoader()

  // 统一内存缓存：缓存所有尺寸的图片，统一管理
  private let imageCache = NSCache<NSString, NSImage>()
  private var memoryPressureSource: DispatchSourceMemoryPressure?
  // 缩略图并发控制，避免滚动时同时解码过多图片
  private let thumbnailLimiter = ConcurrencyLimiter(maxConcurrent: 4)
  // 去重中的缩略图任务，避免重复加载同一图片
  private var thumbnailLoadTasks: [NSString: Task<NSImage?, Never>] = [:]

  // 后台处理队列
  private let processingQueue = DispatchQueue(
    label: "com.soyotube.Picser.imageloader.processing",
    qos: .userInitiated,
    attributes: .concurrent
  )

  // 缓存同步队列
  private let cacheQueue = DispatchQueue(
    label: "com.yototube.Picser.imageloader.cache",
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

    let key = cacheKey(for: url, suffix: "_thumb")
    if let existing = thumbnailLoadTasks[key] {
      return await existing.value
    }

    let task = Task { [weak self] () -> NSImage? in
      guard let self else { return nil }
      return await self.loadThumbnailInternal(for: url)
    }
    thumbnailLoadTasks[key] = task
    let image = await task.value
    thumbnailLoadTasks[key] = nil
    return image
  }

  /// 缩略图加载核心逻辑（带限流与去重）
  private func loadThumbnailInternal(for url: URL) async -> NSImage? {
    if let cached = cachedThumbnail(for: url) {
      return cached
    }

    // 2. 尝试从磁盘缓存快速加载
    if let metadata = await DiskCache.shared.retrieve(forKey: url.path),
       let image = NSImage(data: metadata.thumbnailData) {
      await setCachedImage(image, for: url, suffix: "_thumb")
      return image
    }

    // 3. 重新生成缩略图（受并发限制）
    return await generateThumbnail(for: url)
  }

  /// 生成缩略图并缓存（优化版本）
  private func generateThumbnail(for url: URL) async -> NSImage? {
    await thumbnailLimiter.acquire()
    defer { Task { await self.thumbnailLimiter.release() } }

    // 1. 在后台队列生成缩略图数据
    let thumbnailData = await Task.detached(priority: .userInitiated) {
      self.createThumbnailData(from: url, maxPixelSize: 256)
    }.value

    guard let data = thumbnailData else { return nil }

    // 2. 创建缩略图
    guard let image = NSImage(data: data) else { return nil }

    // 3. 缓存到内存
    await setCachedImage(image, for: url, suffix: "_thumb")

    createAndCacheMetadata(for: url)

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
    let ext = url.pathExtension.lowercased()

    // 矢量格式特殊处理：使用 NSImage 原生支持
    if FormatUtils.supports(.isVector, fileExtension: ext) {
      return await loadSVGImage(from: url)
    }

    // 动画格式特殊处理：保留动画数据
    if FormatUtils.supports(.supportsAnimation, fileExtension: ext) {
      if let data = await readFileData(from: url) {
        return NSImage(data: data)
      }
    }

    // 静态位图处理：EXIF 方向矫正
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

    let ext = url.pathExtension.lowercased()

    // 矢量格式和动画格式直接返回完整图
    // 矢量格式：无需下采样
    // 动画格式：保留动画数据
    if FormatUtils.supports(.isVector, fileExtension: ext)
       || FormatUtils.supports(.supportsAnimation, fileExtension: ext) {
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
  private func createAndCacheMetadata(for url: URL) {
    Task.detached(priority: .utility) {
      guard let data = self.createThumbnailData(from: url, maxPixelSize: 256),
            let metadata = MetadataCache(fromUrl: url, thumbnailData: data) else {
        return
      }
      await DiskCache.shared.store(metadata: metadata, forKey: url.path)
    }
  }

  /// 从原始图片文件创建一个小尺寸、高压缩率的缩略图二进制数据 (Data)
  nonisolated private func createThumbnailData(from url: URL, maxPixelSize: Int) -> Data? {
    let ext = url.pathExtension.lowercased()

    // 矢量格式特殊处理：先加载为 NSImage，再缩放
    if FormatUtils.supports(.isVector, fileExtension: ext) {
      guard let data = try? Data(contentsOf: url, options: .mappedIfSafe),
            let svgImage = NSImage(data: data) else {
        return nil
      }

      // 处理无尺寸 SVG
      if svgImage.size.width == 0 || svgImage.size.height == 0 {
        svgImage.size = NSSize(width: 512, height: 512)
      }

      // 缩放 SVG
      guard let resized = resizeImage(svgImage, maxSize: maxPixelSize) else {
        return nil
      }

      // 转换为 PNG 数据（SVG 通常有透明背景）
      guard let tiffData = resized.tiffRepresentation,
            let bitmapRep = NSBitmapImageRep(data: tiffData) else {
        return nil
      }

      return bitmapRep.representation(using: .png, properties: [:])
    }

    // 位图格式：使用 ImageIO 高效下采样
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

    let bitmapRep = NSBitmapImageRep(cgImage: cgImage)

    // 如果原图带透明通道，则使用 PNG 保留透明度；否则使用压缩率 70% 的 JPEG
    if bitmapRep.hasAlpha {
      return bitmapRep.representation(using: .png, properties: [:])
    } else {
      return bitmapRep.representation(using: .jpeg, properties: [.compressionFactor: 0.7])
    }
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

  /// SVG 加载：使用 NSImage 原生支持（macOS 10.15+）
  ///
  /// **已知限制**：
  /// - 不支持 SVG 动画（SMIL/CSS）
  /// - 如果 SVG 文件使用实体引用（如 `&ns_svg;`）而非标准 namespace URI，
  ///   会产生 "namespace warning: xmlns: URI is not absolute" 警告。
  ///   这是底层 libxml2 解析器的警告，不影响功能，可忽略。
  private func loadSVGImage(from url: URL) async -> NSImage? {
    guard let data = await readFileData(from: url) else { return nil }

    // macOS 原生支持 SVG 加载
    guard let image = NSImage(data: data) else { return nil }

    // 处理无尺寸 SVG：设置合理的默认尺寸
    if image.size.width == 0 || image.size.height == 0 {
      image.size = NSSize(width: 512, height: 512)
    }

    return image
  }

  /// 将 NSImage 缩放到指定最大尺寸（保持宽高比）
  nonisolated private func resizeImage(_ image: NSImage, maxSize: Int) -> NSImage? {
    let size = image.size
    guard size.width > 0 && size.height > 0 else { return nil }

    // 计算缩放后的尺寸（保持宽高比）
    let aspectRatio = size.width / size.height
    var newSize: NSSize
    if size.width > size.height {
      newSize = NSSize(width: CGFloat(maxSize), height: CGFloat(maxSize) / aspectRatio)
    } else {
      newSize = NSSize(width: CGFloat(maxSize) * aspectRatio, height: CGFloat(maxSize))
    }

    // 创建缩放后的图片
    let newImage = NSImage(size: newSize)
    newImage.lockFocus()
    image.draw(
      in: NSRect(origin: .zero, size: newSize),
      from: NSRect(origin: .zero, size: size),
      operation: .copy,
      fraction: 1.0
    )
    newImage.unlockFocus()

    return newImage
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
        // 优先触发缩略图缓存，确保切换更顺畅
        _ = await self.loadThumbnail(for: url)
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
