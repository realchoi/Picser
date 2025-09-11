//
//  ExifExtractor.swift
//  PicTube
//
//  Extracted from ContentView to keep view logic minimal.
//

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
        return ExifInfo.from(exifDictionary: exifDict, fileName: url.lastPathComponent)
      }
    }

    // 如果缓存中没有，直接从文件提取 EXIF 数据
    return try await extractExifInfoFromFile(url: url)
  }

  /// 直接从文件提取 EXIF 信息
  static func extractExifInfoFromFile(url: URL) async throws -> ExifInfo {
    return try await Task.detached(priority: .userInitiated) {
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

      return ExifInfo.from(exifDictionary: exifDict, fileName: url.lastPathComponent)
    }.value
  }
}

