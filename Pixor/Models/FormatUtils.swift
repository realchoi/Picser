//
//  FormatUtils.swift
//  Pixor
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
    default: return ext.isEmpty ? L10n.string("unknown_format") : ext
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
    return String(format: L10n.string("iso_value_format"), first)
  }

  static func focalLength(_ mm: Double?) -> String? {
    guard let mm else { return nil }
    return String(format: "%.0fmm", mm)
  }

  static func focalLength35mm(_ mm: Int?) -> String? {
    guard let mm else { return nil }
    return String(format: L10n.string("focal_length_35mm_format"), mm)
  }

  static func exposureProgram(_ program: Int?) -> String? {
    guard let program else { return nil }
    switch program {
    case 0: return L10n.string("exposure_program_0")
    case 1: return L10n.string("exposure_program_1")
    case 2: return L10n.string("exposure_program_2")
    case 3: return L10n.string("exposure_program_3")
    case 4: return L10n.string("exposure_program_4")
    case 5: return L10n.string("exposure_program_5")
    case 6: return L10n.string("exposure_program_6")
    case 7: return L10n.string("exposure_program_7")
    case 8: return L10n.string("exposure_program_8")
    default: return String(format: L10n.string("exif_other_format"), program)
    }
  }

  static func meteringMode(_ mode: Int?) -> String? {
    guard let mode else { return nil }
    switch mode {
    case 0: return L10n.string("metering_mode_0")
    case 1: return L10n.string("metering_mode_1")
    case 2: return L10n.string("metering_mode_2")
    case 3: return L10n.string("metering_mode_3")
    case 4: return L10n.string("metering_mode_4")
    case 5: return L10n.string("metering_mode_5")
    case 6: return L10n.string("metering_mode_6")
    default: return String(format: L10n.string("exif_other_format"), mode)
    }
  }

  static func flash(_ code: Int?) -> String? {
    guard let code else { return nil }
    switch code {
    case 0: return L10n.string("flash_0")
    case 1: return L10n.string("flash_1")
    case 5: return L10n.string("flash_5")
    case 7: return L10n.string("flash_7")
    case 9: return L10n.string("flash_9")
    case 13: return L10n.string("flash_13")
    case 15: return L10n.string("flash_15")
    case 16: return L10n.string("flash_16")
    case 24: return L10n.string("flash_24")
    case 25: return L10n.string("flash_25")
    case 29: return L10n.string("flash_29")
    case 31: return L10n.string("flash_31")
    case 32: return L10n.string("flash_32")
    default: return String(format: L10n.string("exif_other_format"), code)
    }
  }

  static func whiteBalance(_ value: Int?) -> String? {
    guard let value else { return nil }
    switch value {
    case 0: return L10n.string("white_balance_auto")
    case 1: return L10n.string("white_balance_manual")
    default: return String(format: L10n.string("exif_other_format"), value)
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
      ? L10n.string("gps_altitude_below_sea_level")
      : L10n.string("gps_altitude_above_sea_level")
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
    case 65535: return L10n.string("color_space_uncalibrated")
    default: return String(format: L10n.string("exif_other_format"), code)
    }
  }

  static func orientation(_ value: Int?) -> String? {
    guard let value else { return nil }
    switch value {
    case 1: return L10n.string("orientation_1")
    case 2: return L10n.string("orientation_2")
    case 3: return L10n.string("orientation_3")
    case 4: return L10n.string("orientation_4")
    case 5: return L10n.string("orientation_5")
    case 6: return L10n.string("orientation_6")
    case 7: return L10n.string("orientation_7")
    case 8: return L10n.string("orientation_8")
    default: return String(format: L10n.string("exif_other_format"), value)
    }
  }

  static func resolution(_ value: Double?) -> String? {
    guard let value else { return nil }
    return String(format: "%.0f", value)
  }

  static func resolutionUnit(_ unit: Int?) -> String? {
    guard let unit else { return nil }
    switch unit {
    case 1: return L10n.string("resolution_unit_none")
    case 2: return L10n.string("resolution_unit_inch")
    case 3: return L10n.string("resolution_unit_centimeter")
    default: return String(format: L10n.string("exif_other_format"), unit)
    }
  }
}
