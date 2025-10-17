//
//  ExifInfo.swift
//
//  Created by Eric Cai on 2025/09/06.
//

import Foundation
import ImageIO

/// EXIF 信息结构体，用于展示图片的详细元数据
struct ExifInfo {
  // MARK: - 基本文件信息
  let fileName: String
  let filePath: String
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
  static func from(exifDictionary: [String: Any], fileURL: URL) -> ExifInfo {
    return ExifInfo(
      fileName: fileURL.lastPathComponent,
      filePath: FormatUtils.displayFilePath(from: fileURL),
      fileSize: formatFileSize(exifDictionary["FileSize"] as? Int64 ?? 0),
      fileFormat: FormatUtils.fileFormat(from: fileURL.lastPathComponent),
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
    return FormatUtils.fileSizeString(bytes)
  }

  // 已迁移至 FormatUtils.fileFormat(from:)

  fileprivate static func formatDate(_ timestamp: TimeInterval?) -> String {
    guard let timestamp = timestamp else { return L10n.string("unknown_value") }
    return FormatUtils.dateTimeString(from: timestamp)
  }

  fileprivate static func formatFNumber(_ fNumber: Double?) -> String? {
    return FormatUtils.fNumber(fNumber)
  }

  fileprivate static func formatExposureTime(_ time: Double?) -> String? {
    return FormatUtils.exposureTime(time)
  }

  fileprivate static func formatISO(_ isoArray: [Int]?) -> String? {
    return FormatUtils.iso(isoArray)
  }

  fileprivate static func formatFocalLength(_ length: Double?) -> String? {
    return FormatUtils.focalLength(length)
  }

  fileprivate static func formatFocalLength35mm(_ length: Int?) -> String? {
    return FormatUtils.focalLength35mm(length)
  }

  fileprivate static func formatExposureProgram(_ program: Int?) -> String? {
    return FormatUtils.exposureProgram(program)
  }

  fileprivate static func formatMeteringMode(_ mode: Int?) -> String? {
    return FormatUtils.meteringMode(mode)
  }

  fileprivate static func formatFlash(_ flash: Int?) -> String? {
    return FormatUtils.flash(flash)
  }

  fileprivate static func formatWhiteBalance(_ wb: Int?) -> String? {
    return FormatUtils.whiteBalance(wb)
  }

  fileprivate static func formatGPSCoordinate(_ coordinate: [Double]?, ref: String?) -> String? {
    return FormatUtils.gpsCoordinate(coordinate, ref: ref)
  }

  fileprivate static func formatGPSAltitude(_ altitude: Double?, ref: Int?) -> String? {
    return FormatUtils.gpsAltitude(altitude, ref: ref)
  }

  fileprivate static func formatGPSDateTime(date: String?, time: [Double]?) -> String? {
    return FormatUtils.gpsDateTime(date: date, time: time)
  }

  fileprivate static func formatColorSpace(_ space: Int?) -> String? {
    return FormatUtils.colorSpace(space)
  }

  fileprivate static func formatOrientation(_ orientation: Int?) -> String? {
    return FormatUtils.orientation(orientation)
  }

  fileprivate static func formatResolution(_ resolution: Double?) -> String? {
    return FormatUtils.resolution(resolution)
  }

  fileprivate static func formatResolutionUnit(_ unit: Int?) -> String? {
    return FormatUtils.resolutionUnit(unit)
  }
}
