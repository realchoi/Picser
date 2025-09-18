//
//  FormatUtils.swift
//  Pixo
//
//  Created by Eric Cai on 2025/09/10.
//

import Foundation

enum FormatUtils {
  /// 统一的文件大小格式化方法（KB/MB/GB，文件风格）
  static func fileSizeString(_ bytes: Int64) -> String {
    let formatter = ByteCountFormatter()
    formatter.allowedUnits = [.useKB, .useMB, .useGB]
    formatter.countStyle = .file
    return formatter.string(fromByteCount: bytes)
  }

  /// 统一的日期时间格式化（.medium 日期 + .medium 时间，跟随系统本地化）
  static func dateTimeString(from timestamp: TimeInterval) -> String {
    let date = Date(timeIntervalSince1970: timestamp)
    let formatter = DateFormatter()
    formatter.dateStyle = .medium
    formatter.timeStyle = .medium
    formatter.locale = Locale.current
    return formatter.string(from: date)
  }

  // MARK: - EXIF 值格式化

  /// 文件格式（根据文件名后缀，未知则返回本地化的“未知格式”）
  static func fileFormat(from fileName: String) -> String {
    let ext = (fileName as NSString).pathExtension.uppercased()
    switch ext {
    case "JPG", "JPEG": return "JPEG"
    case "PNG": return "PNG"
    case "GIF": return "GIF"
    case "HEIC": return "HEIC"
    case "TIFF": return "TIFF"
    case "WEBP": return "WebP"
    default: return ext.isEmpty ? "unknown_format".localized : ext
    }
  }

  static func fNumber(_ value: Double?) -> String? {
    guard let value else { return nil }
    return String(format: "f/%.1f", value)
  }

  static func exposureTime(_ seconds: Double?) -> String? {
    guard let seconds else { return nil }
    if seconds >= 1.0 {
      return String(format: "%.1fs", seconds)
    } else {
      return String(format: "1/%.0fs", 1.0 / seconds)
    }
  }

  static func iso(_ isoArray: [Int]?) -> String? {
    guard let isoArray, let first = isoArray.first else { return nil }
    return String(format: "iso_value_format".localized, first)
  }

  static func focalLength(_ mm: Double?) -> String? {
    guard let mm else { return nil }
    return String(format: "%.0fmm", mm)
  }

  static func focalLength35mm(_ mm: Int?) -> String? {
    guard let mm else { return nil }
    return String(format: "focal_length_35mm_format".localized, mm)
  }

  static func exposureProgram(_ program: Int?) -> String? {
    guard let program else { return nil }
    switch program {
    case 0: return "exposure_program_0".localized
    case 1: return "exposure_program_1".localized
    case 2: return "exposure_program_2".localized
    case 3: return "exposure_program_3".localized
    case 4: return "exposure_program_4".localized
    case 5: return "exposure_program_5".localized
    case 6: return "exposure_program_6".localized
    case 7: return "exposure_program_7".localized
    case 8: return "exposure_program_8".localized
    default: return String(format: "exif_other_format".localized, program)
    }
  }

  static func meteringMode(_ mode: Int?) -> String? {
    guard let mode else { return nil }
    switch mode {
    case 0: return "metering_mode_0".localized
    case 1: return "metering_mode_1".localized
    case 2: return "metering_mode_2".localized
    case 3: return "metering_mode_3".localized
    case 4: return "metering_mode_4".localized
    case 5: return "metering_mode_5".localized
    case 6: return "metering_mode_6".localized
    default: return String(format: "exif_other_format".localized, mode)
    }
  }

  static func flash(_ code: Int?) -> String? {
    guard let code else { return nil }
    switch code {
    case 0: return "flash_0".localized
    case 1: return "flash_1".localized
    case 5: return "flash_5".localized
    case 7: return "flash_7".localized
    case 9: return "flash_9".localized
    case 13: return "flash_13".localized
    case 15: return "flash_15".localized
    case 16: return "flash_16".localized
    case 24: return "flash_24".localized
    case 25: return "flash_25".localized
    case 29: return "flash_29".localized
    case 31: return "flash_31".localized
    case 32: return "flash_32".localized
    default: return String(format: "exif_other_format".localized, code)
    }
  }

  static func whiteBalance(_ value: Int?) -> String? {
    guard let value else { return nil }
    switch value {
    case 0: return "white_balance_auto".localized
    case 1: return "white_balance_manual".localized
    default: return String(format: "exif_other_format".localized, value)
    }
  }

  static func gpsCoordinate(_ coordinate: [Double]?, ref: String?) -> String? {
    guard let coordinate, coordinate.count >= 3, let ref else { return nil }
    let degrees = coordinate[0]
    let minutes = coordinate[1]
    let seconds = coordinate[2]
    let decimal = degrees + minutes / 60.0 + seconds / 3600.0
    return String(format: "%.6f° %@", decimal, ref)
  }

  static func gpsAltitude(_ altitude: Double?, ref: Int?) -> String? {
    guard let altitude else { return nil }
    let refString = (ref == 1)
      ? "gps_altitude_below_sea_level".localized
      : "gps_altitude_above_sea_level".localized
    return String(format: "%.1fm %@", altitude, refString)
  }

  static func gpsDateTime(date: String?, time: [Double]?) -> String? {
    guard let date, let time, time.count >= 3 else { return nil }
    let timeString = String(format: "%02.0f:%02.0f:%02.0f UTC", time[0], time[1], time[2])
    return "\(date) \(timeString)"
  }

  static func colorSpace(_ code: Int?) -> String? {
    guard let code else { return nil }
    switch code {
    case 1: return "sRGB"
    case 65535: return "color_space_uncalibrated".localized
    default: return String(format: "exif_other_format".localized, code)
    }
  }

  static func orientation(_ value: Int?) -> String? {
    guard let value else { return nil }
    switch value {
    case 1: return "orientation_1".localized
    case 2: return "orientation_2".localized
    case 3: return "orientation_3".localized
    case 4: return "orientation_4".localized
    case 5: return "orientation_5".localized
    case 6: return "orientation_6".localized
    case 7: return "orientation_7".localized
    case 8: return "orientation_8".localized
    default: return String(format: "exif_other_format".localized, value)
    }
  }

  static func resolution(_ value: Double?) -> String? {
    guard let value else { return nil }
    return String(format: "%.0f", value)
  }

  static func resolutionUnit(_ unit: Int?) -> String? {
    guard let unit else { return nil }
    switch unit {
    case 1: return "resolution_unit_none".localized
    case 2: return "resolution_unit_inch".localized
    case 3: return "resolution_unit_centimeter".localized
    default: return String(format: "exif_other_format".localized, unit)
    }
  }
}
