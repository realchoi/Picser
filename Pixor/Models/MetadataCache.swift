// Pixor/Models/MetadataCache.swift

import AppKit
import Foundation

/// 定义原始图片文件的类型，以便进行差异化加载
enum OriginalImageFormat: UInt8, Codable {
  case jpeg
  case png
  case gif
  case heic
  case other  // 其他静态图片格式
}

/// 缓存包的结构体，它将被序列化为二进制文件
struct MetadataCache: Codable {
  // --- 文件头 (Header) ---
  /// 魔数，用于快速识别文件类型。固定值 0x50494354 代表 "PICT"
  let magicNumber: UInt32 = 0x5049_4354
  /// 缓存结构的版本号，便于未来升级
  let version: UInt8 = 2

  // --- 元数据 (Metadata) ---
  /// 原始文件最后修改时间的 Unix 时间戳
  let originalFileTimestamp: TimeInterval
  /// 原始文件的格式
  let originalFormat: OriginalImageFormat
  /// 原始图片的像素宽度
  let originalWidth: Int
  /// 原始图片的像素高度
  let originalHeight: Int

  // --- 负载数据 (Payload) ---
  /// 用于快速预览的微缩略图的二进制数据 (例如，压缩后的 WebP 或 JPG 数据)
  let thumbnailData: Data
  /// EXIF 信息数据，序列化为二进制格式
  let exifData: Data

  // 通过定义 CodingKeys，我们明确告诉 Codable 只对列出的 key 进行编解码。
  // 现在将 magicNumber 和 version 一并持久化，以便在读取时进行有效性校验。
  // 这里我们使用 private 修饰，因为这些 key 只用于编解码，不应该暴露给外部。
  private enum CodingKeys: String, CodingKey {
    case magicNumber
    case version
    case originalFileTimestamp
    case originalFormat
    case originalWidth
    case originalHeight
    case thumbnailData
    case exifData
  }

  /// 便利的构造器，用于创建一个新的缓存对象
  init?(fromUrl url: URL, thumbnailData: Data) {
    guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
      let modificationDate = attributes[.modificationDate] as? Date,
      let imageSource = CGImageSourceCreateWithURL(url as CFURL, nil),
      let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [CFString: Any],
      let width = properties[kCGImagePropertyPixelWidth] as? Int,
      let height = properties[kCGImagePropertyPixelHeight] as? Int
    else {
      return nil
    }

    self.originalFileTimestamp = modificationDate.timeIntervalSince1970
    self.originalWidth = width
    self.originalHeight = height
    self.thumbnailData = thumbnailData

    // 根据文件后缀判断格式
    switch url.pathExtension.lowercased() {
    case "jpg", "jpeg":
      self.originalFormat = .jpeg
    case "png":
      self.originalFormat = .png
    case "gif":
      self.originalFormat = .gif
    case "heic":
      self.originalFormat = .heic
    default:
      self.originalFormat = .other
    }

    // 提取 EXIF 数据并序列化
    var exifDict: [String: Any] = [:]

    // 从 properties 中提取各种元数据
    if let exifProperties = properties[kCGImagePropertyExifDictionary] as? [CFString: Any] {
      for (key, value) in exifProperties {
        exifDict["Exif_\(key)"] = value
      }
    }

    if let tiffProperties = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any] {
      for (key, value) in tiffProperties {
        exifDict["TIFF_\(key)"] = value
      }
    }

    if let gpsProperties = properties[kCGImagePropertyGPSDictionary] as? [CFString: Any] {
      for (key, value) in gpsProperties {
        exifDict["GPS_\(key)"] = value
      }
    }

    // 添加基础属性
    exifDict["ImageWidth"] = width
    exifDict["ImageHeight"] = height
    exifDict["FileSize"] = attributes[.size] as? Int64 ?? 0
    exifDict["FileModificationDate"] = modificationDate.timeIntervalSince1970

    // 序列化 EXIF 数据
    do {
      self.exifData = try PropertyListSerialization.data(
        fromPropertyList: exifDict,
        format: .binary,
        options: 0
      )
    } catch {
      // 如果序列化失败，使用空数据
      self.exifData = Data()
    }
  }

  /// 获取反序列化的 EXIF 数据字典
  func getExifDictionary() -> [String: Any] {
    do {
      if let dict = try PropertyListSerialization.propertyList(
        from: exifData,
        options: [],
        format: nil
      ) as? [String: Any] {
        return dict
      }
    } catch {
      // 反序列化失败，返回空字典
    }
    return [:]
  }
}
