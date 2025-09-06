//
//  ExifInfo.swift
//  PicTube
//
//  Created by Eric Cai on 2025/09/06.
//

import Foundation
import ImageIO

/// EXIF 信息结构体，用于展示图片的详细元数据
struct ExifInfo {
  // MARK: - 基本文件信息
  let fileName: String
  let fileSize: String
  let fileFormat: String
  let imageWidth: Int
  let imageHeight: Int
  let fileModificationDate: String

  // MARK: - 相机和拍摄信息
  let cameraMake: String?
  let cameraModel: String?
  let lensMake: String?
  let lensModel: String?
  let software: String?

  // MARK: - 拍摄参数
  let fNumber: String?  // 光圈
  let exposureTime: String?  // 快门速度
  let isoSpeed: String?  // ISO
  let focalLength: String?  // 焦距
  let focalLength35mm: String?  // 35mm等效焦距
  let exposureProgram: String?  // 曝光程序
  let meteringMode: String?  // 测光模式
  let flash: String?  // 闪光灯
  let whiteBalance: String?  // 白平衡

  // MARK: - GPS 信息
  let gpsLatitude: String?
  let gpsLongitude: String?
  let gpsAltitude: String?
  let gpsDateTime: String?

  // MARK: - 颜色和技术信息
  let colorSpace: String?
  let orientation: String?
  let xResolution: String?
  let yResolution: String?
  let resolutionUnit: String?

  // MARK: - 创建方法

  /// 从 EXIF 字典创建 ExifInfo 结构体
  static func from(exifDictionary: [String: Any], fileName: String) -> ExifInfo {
    return ExifInfo(
      fileName: fileName,
      fileSize: formatFileSize(exifDictionary["FileSize"] as? Int64 ?? 0),
      fileFormat: determineFileFormat(from: fileName),
      imageWidth: exifDictionary["ImageWidth"] as? Int ?? 0,
      imageHeight: exifDictionary["ImageHeight"] as? Int ?? 0,
      fileModificationDate: formatDate(exifDictionary["FileModificationDate"] as? TimeInterval),

      // 相机信息
      cameraMake: exifDictionary["TIFF_Make"] as? String,
      cameraModel: exifDictionary["TIFF_Model"] as? String,
      lensMake: exifDictionary["Exif_LensMake"] as? String,
      lensModel: exifDictionary["Exif_LensModel"] as? String,
      software: exifDictionary["TIFF_Software"] as? String,

      // 拍摄参数
      fNumber: formatFNumber(exifDictionary["Exif_FNumber"] as? Double),
      exposureTime: formatExposureTime(exifDictionary["Exif_ExposureTime"] as? Double),
      isoSpeed: formatISO(exifDictionary["Exif_ISOSpeedRatings"] as? [Int]),
      focalLength: formatFocalLength(exifDictionary["Exif_FocalLength"] as? Double),
      focalLength35mm: formatFocalLength35mm(exifDictionary["Exif_FocalLenIn35mmFilm"] as? Int),
      exposureProgram: formatExposureProgram(exifDictionary["Exif_ExposureProgram"] as? Int),
      meteringMode: formatMeteringMode(exifDictionary["Exif_MeteringMode"] as? Int),
      flash: formatFlash(exifDictionary["Exif_Flash"] as? Int),
      whiteBalance: formatWhiteBalance(exifDictionary["Exif_WhiteBalance"] as? Int),

      // GPS 信息
      gpsLatitude: formatGPSCoordinate(
        exifDictionary["GPS_Latitude"] as? [Double],
        ref: exifDictionary["GPS_LatitudeRef"] as? String
      ),
      gpsLongitude: formatGPSCoordinate(
        exifDictionary["GPS_Longitude"] as? [Double],
        ref: exifDictionary["GPS_LongitudeRef"] as? String
      ),
      gpsAltitude: formatGPSAltitude(
        exifDictionary["GPS_Altitude"] as? Double,
        ref: exifDictionary["GPS_AltitudeRef"] as? Int
      ),
      gpsDateTime: formatGPSDateTime(
        date: exifDictionary["GPS_DateStamp"] as? String,
        time: exifDictionary["GPS_TimeStamp"] as? [Double]
      ),

      // 颜色和技术信息
      colorSpace: formatColorSpace(exifDictionary["Exif_ColorSpace"] as? Int),
      orientation: formatOrientation(exifDictionary["TIFF_Orientation"] as? Int),
      xResolution: formatResolution(exifDictionary["TIFF_XResolution"] as? Double),
      yResolution: formatResolution(exifDictionary["TIFF_YResolution"] as? Double),
      resolutionUnit: formatResolutionUnit(exifDictionary["TIFF_ResolutionUnit"] as? Int)
    )
  }
}

// MARK: - 格式化辅助方法

extension ExifInfo {

  fileprivate static func formatFileSize(_ bytes: Int64) -> String {
    let formatter = ByteCountFormatter()
    formatter.allowedUnits = [.useKB, .useMB, .useGB]
    formatter.countStyle = .file
    return formatter.string(fromByteCount: bytes)
  }

  fileprivate static func determineFileFormat(from fileName: String) -> String {
    let ext = (fileName as NSString).pathExtension.uppercased()
    switch ext {
    case "JPG", "JPEG": return "JPEG"
    case "PNG": return "PNG"
    case "GIF": return "GIF"
    case "HEIC": return "HEIC"
    case "TIFF": return "TIFF"
    case "WEBP": return "WebP"
    default: return ext.isEmpty ? "未知格式" : ext
    }
  }

  fileprivate static func formatDate(_ timestamp: TimeInterval?) -> String {
    guard let timestamp = timestamp else { return "未知" }
    let date = Date(timeIntervalSince1970: timestamp)
    let formatter = DateFormatter()
    formatter.dateStyle = .medium
    formatter.timeStyle = .medium
    formatter.locale = Locale.current
    return formatter.string(from: date)
  }

  fileprivate static func formatFNumber(_ fNumber: Double?) -> String? {
    guard let fNumber = fNumber else { return nil }
    return String(format: "f/%.1f", fNumber)
  }

  fileprivate static func formatExposureTime(_ time: Double?) -> String? {
    guard let time = time else { return nil }
    if time >= 1.0 {
      return String(format: "%.1fs", time)
    } else {
      return String(format: "1/%.0fs", 1.0 / time)
    }
  }

  fileprivate static func formatISO(_ isoArray: [Int]?) -> String? {
    guard let isoArray = isoArray, let iso = isoArray.first else { return nil }
    return "ISO \(iso)"
  }

  fileprivate static func formatFocalLength(_ length: Double?) -> String? {
    guard let length = length else { return nil }
    return String(format: "%.0fmm", length)
  }

  fileprivate static func formatFocalLength35mm(_ length: Int?) -> String? {
    guard let length = length else { return nil }
    return String(format: "%dmm (35mm等效)", length)
  }

  fileprivate static func formatExposureProgram(_ program: Int?) -> String? {
    guard let program = program else { return nil }
    switch program {
    case 0: return "未定义"
    case 1: return "手动"
    case 2: return "程序自动"
    case 3: return "光圈优先"
    case 4: return "快门优先"
    case 5: return "创意程序"
    case 6: return "动作程序"
    case 7: return "人像模式"
    case 8: return "风景模式"
    default: return "其他(\(program))"
    }
  }

  fileprivate static func formatMeteringMode(_ mode: Int?) -> String? {
    guard let mode = mode else { return nil }
    switch mode {
    case 0: return "未知"
    case 1: return "平均测光"
    case 2: return "中央重点测光"
    case 3: return "点测光"
    case 4: return "多点测光"
    case 5: return "评估测光"
    case 6: return "局部测光"
    default: return "其他(\(mode))"
    }
  }

  fileprivate static func formatFlash(_ flash: Int?) -> String? {
    guard let flash = flash else { return nil }
    switch flash {
    case 0: return "未闪光"
    case 1: return "闪光"
    case 5: return "频闪，未检测到反射光"
    case 7: return "频闪，检测到反射光"
    case 9: return "强制闪光"
    case 13: return "强制闪光，未检测到反射光"
    case 15: return "强制闪光，检测到反射光"
    case 16: return "未闪光，强制关闭"
    case 24: return "未闪光，自动模式"
    case 25: return "闪光，自动模式"
    case 29: return "闪光，自动模式，未检测到反射光"
    case 31: return "闪光，自动模式，检测到反射光"
    case 32: return "未闪光，无闪光功能"
    default: return "其他(\(flash))"
    }
  }

  fileprivate static func formatWhiteBalance(_ wb: Int?) -> String? {
    guard let wb = wb else { return nil }
    switch wb {
    case 0: return "自动"
    case 1: return "手动"
    default: return "其他(\(wb))"
    }
  }

  fileprivate static func formatGPSCoordinate(_ coordinate: [Double]?, ref: String?) -> String? {
    guard let coordinate = coordinate, coordinate.count >= 3, let ref = ref else { return nil }
    let degrees = coordinate[0]
    let minutes = coordinate[1]
    let seconds = coordinate[2]
    let decimal = degrees + minutes / 60.0 + seconds / 3600.0
    return String(format: "%.6f° %@", decimal, ref)
  }

  fileprivate static func formatGPSAltitude(_ altitude: Double?, ref: Int?) -> String? {
    guard let altitude = altitude else { return nil }
    let refString = (ref == 1) ? "海平面以下" : "海平面以上"
    return String(format: "%.1fm %@", altitude, refString)
  }

  fileprivate static func formatGPSDateTime(date: String?, time: [Double]?) -> String? {
    guard let date = date, let time = time, time.count >= 3 else { return nil }
    let timeString = String(format: "%02.0f:%02.0f:%02.0f UTC", time[0], time[1], time[2])
    return "\(date) \(timeString)"
  }

  fileprivate static func formatColorSpace(_ space: Int?) -> String? {
    guard let space = space else { return nil }
    switch space {
    case 1: return "sRGB"
    case 65535: return "未校准"
    default: return "其他(\(space))"
    }
  }

  fileprivate static func formatOrientation(_ orientation: Int?) -> String? {
    guard let orientation = orientation else { return nil }
    switch orientation {
    case 1: return "正常"
    case 2: return "水平翻转"
    case 3: return "旋转180°"
    case 4: return "垂直翻转"
    case 5: return "顺时针旋转90°+水平翻转"
    case 6: return "顺时针旋转90°"
    case 7: return "逆时针旋转90°+水平翻转"
    case 8: return "逆时针旋转90°"
    default: return "其他(\(orientation))"
    }
  }

  fileprivate static func formatResolution(_ resolution: Double?) -> String? {
    guard let resolution = resolution else { return nil }
    return String(format: "%.0f", resolution)
  }

  fileprivate static func formatResolutionUnit(_ unit: Int?) -> String? {
    guard let unit = unit else { return nil }
    switch unit {
    case 1: return "无单位"
    case 2: return "英寸"
    case 3: return "厘米"
    default: return "其他(\(unit))"
    }
  }
}
