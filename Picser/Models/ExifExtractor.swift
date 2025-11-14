//
//  ExifExtractor.swift
//
//  Extracted from ContentView to keep view logic minimal.
//

import AppKit
import Foundation
import ImageIO

/// EXIF 信息提取错误类型
enum ExifExtractionError: Error {
  case failedToCreateImageSource
  case failedToExtractProperties
}

/// EXIF 加载与解析。
/// 功能: 统一从磁盘缓存或文件中提取 EXIF 的逻辑，定义错误类型 ExifExtractionError，并提供 ExifExtractor.loadExifInfo(for:)。
enum ExifExtractor {
  /// 加载图片的 EXIF 信息：优先使用磁盘缓存，否则直接从文件提取
  static func loadExifInfo(for url: URL) async throws -> ExifInfo {
    // 尝试从缓存获取 EXIF 数据
    if let metadata = await DiskCache.shared.retrieve(forKey: url.path) {
      let exifDict = metadata.getExifDictionary()
      if !exifDict.isEmpty {
        return ExifInfo.from(exifDictionary: exifDict, fileURL: url)
      }
    }

    // 如果缓存中没有，直接从文件提取 EXIF 数据
    return try await extractExifInfoFromFile(url: url)
  }

  /// 直接从文件提取 EXIF 信息
  static func extractExifInfoFromFile(url: URL) async throws -> ExifInfo {
    return try await Task.detached(priority: .userInitiated) {
      let ext = url.pathExtension.lowercased()

      // 不支持 EXIF 的格式特殊处理：只提供基础文件信息
      if !FormatUtils.supports(.supportsEXIF, fileExtension: ext) {
        return try extractBasicInfoWithoutExif(url: url)
      }

      // 支持 EXIF 的位图格式：使用 CGImageSource 读取完整 EXIF
      guard let imageSource = CGImageSourceCreateWithURL(url as CFURL, nil) else {
        throw ExifExtractionError.failedToCreateImageSource
      }

      guard let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [CFString: Any] else {
        throw ExifExtractionError.failedToExtractProperties
      }

      // 获取文件属性
      let attributes = try FileManager.default.attributesOfItem(atPath: url.path)

      // 构建 EXIF 数据字典
      var exifDict: [String: Any] = [:]

      // 添加基础属性
      if let width = properties[kCGImagePropertyPixelWidth] as? Int { exifDict["ImageWidth"] = width }
      if let height = properties[kCGImagePropertyPixelHeight] as? Int { exifDict["ImageHeight"] = height }
      exifDict["FileSize"] = attributes[.size] as? Int64 ?? 0
      if let modificationDate = attributes[.modificationDate] as? Date {
        exifDict["FileModificationDate"] = modificationDate.timeIntervalSince1970
      }

      // 提取各种 EXIF 数据
      if let exifProperties = properties[kCGImagePropertyExifDictionary] as? [CFString: Any] {
        for (key, value) in exifProperties { exifDict["Exif_\(key)"] = value }
      }
      if let tiffProperties = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any] {
        for (key, value) in tiffProperties { exifDict["TIFF_\(key)"] = value }
      }
      if let gpsProperties = properties[kCGImagePropertyGPSDictionary] as? [CFString: Any] {
        for (key, value) in gpsProperties { exifDict["GPS_\(key)"] = value }
      }

      return ExifInfo.from(exifDictionary: exifDict, fileURL: url)
    }.value
  }

  /// 为不支持 EXIF 的格式提取基础信息（仅文件属性和尺寸，无相机元数据）
  private static func extractBasicInfoWithoutExif(url: URL) throws -> ExifInfo {
    // 获取文件属性
    let attributes = try FileManager.default.attributesOfItem(atPath: url.path)

    // 尝试加载图片获取尺寸
    var width = 0
    var height = 0
    if let data = try? Data(contentsOf: url, options: .mappedIfSafe),
       let image = NSImage(data: data) {
      let size = image.size
      // 矢量格式特殊处理：如果没有明确尺寸，设置默认值
      let ext = url.pathExtension.lowercased()
      if FormatUtils.supports(.isVector, fileExtension: ext) && (size.width == 0 || size.height == 0) {
        width = 512
        height = 512
      } else {
        width = Int(size.width)
        height = Int(size.height)
      }
    }

    // 构建基础信息字典（仅文件级别信息，无相机 EXIF）
    var exifDict: [String: Any] = [:]
    exifDict["ImageWidth"] = width
    exifDict["ImageHeight"] = height
    exifDict["FileSize"] = attributes[.size] as? Int64 ?? 0
    if let modificationDate = attributes[.modificationDate] as? Date {
      exifDict["FileModificationDate"] = modificationDate.timeIntervalSince1970
    }

    return ExifInfo.from(exifDictionary: exifDict, fileURL: url)
  }
}
