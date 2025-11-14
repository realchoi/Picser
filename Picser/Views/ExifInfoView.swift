//
//  ExifInfoView.swift
//
//  Created by Eric Cai on 2025/09/06.
//

import AppKit
import SwiftUI

private enum InfoTableLayout {
  static let labelColumnWidth: CGFloat = 150
  static let rowHorizontalPadding: CGFloat = 14
  static let rowVerticalPadding: CGFloat = 8
  static let sectionSpacing: CGFloat = 20
  static let dividerOpacity: Double = 0.45
}

/// EXIF 信息展示视图
struct ExifInfoView: View {
  let exifInfo: ExifInfo

  var body: some View {
    VStack(spacing: 0) {
      // 标题栏
      HStack {
        Text(l10n: "exif_window_title")
          .font(.headline)
          .foregroundColor(.primary)

        Spacer()
      }
      .padding()
      .background(.regularMaterial)

      Divider()

      // 内容区域
      ScrollView(.vertical, showsIndicators: true) {
        VStack(alignment: .leading, spacing: InfoTableLayout.sectionSpacing) {
          // 基本信息部分
          InfoSection(
            title: L10n.string("basic_info_section"),
            items: basicInfoItems
          )

          // 相机信息部分（只在有相机数据时显示）
          if hasCameraInfo {
            InfoSection(
              title: L10n.string("camera_info_section"),
              items: cameraInfoItems
            )
          }

          // 拍摄参数部分（只在有拍摄数据时显示）
          if hasShootingParams {
            InfoSection(
              title: L10n.string("shooting_params_section"),
              items: shootingParamItems
            )
          }

          // 位置信息部分（只在有GPS数据时显示）
          if hasLocationInfo {
            InfoSection(
              title: L10n.string("location_info_section"),
              items: locationInfoItems
            )
          }

          // 技术信息部分（只在有技术数据时显示）
          if hasTechnicalInfo {
            InfoSection(
              title: L10n.string("technical_info_section"),
              items: technicalInfoItems
            )
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }

  // MARK: - 计算属性

  private var basicInfoItems: [InfoItem] {
    [
      InfoItem(
        label: L10n.string("file_name_label"),
        value: exifInfo.fileName
      ),
      InfoItem(
        label: L10n.string("full_path_label"),
        value: filePathDisplayValue
      ),
      InfoItem(
        label: L10n.string("file_size_label"),
        value: exifInfo.fileSize
      ),
      InfoItem(
        label: L10n.string("file_format_label"),
        value: exifInfo.fileFormat
      ),
      InfoItem(
        label: L10n.string("image_dimensions_label"),
        value: "\(exifInfo.imageWidth) × \(exifInfo.imageHeight)"
      ),
      InfoItem(
        label: L10n.string("modification_date_label"),
        value: exifInfo.fileModificationDate
      ),
    ]
  }

  private var filePathDisplayValue: String {
    let trimmed = exifInfo.filePath.trimmingCharacters(in: .whitespacesAndNewlines)
    let placeholder = L10n.string("unknown_value")
    if trimmed.isEmpty || trimmed == placeholder {
      return placeholder
    }
    return trimmed
  }

  private var cameraInfoItems: [InfoItem] {
    var items: [InfoItem] = []

    if let cameraMake = exifInfo.cameraMake {
      items.append(
        InfoItem(
          label: L10n.string("camera_make_label"),
          value: cameraMake
        ))
    }

    if let cameraModel = exifInfo.cameraModel {
      items.append(
        InfoItem(
          label: L10n.string("camera_model_label"),
          value: cameraModel
        ))
    }

    if let lensMake = exifInfo.lensMake {
      items.append(
        InfoItem(
          label: L10n.string("lens_make_label"),
          value: lensMake
        ))
    }

    if let lensModel = exifInfo.lensModel {
      items.append(
        InfoItem(
          label: L10n.string("lens_model_label"),
          value: lensModel
        ))
    }

    if let software = exifInfo.software {
      items.append(
        InfoItem(
          label: L10n.string("software_label"),
          value: software
        ))
    }

    return items
  }

  private var shootingParamItems: [InfoItem] {
    var items: [InfoItem] = []

    if let fNumber = exifInfo.fNumber {
      items.append(
        InfoItem(
          label: L10n.string("aperture_label"),
          value: fNumber
        ))
    }

    if let exposureTime = exifInfo.exposureTime {
      items.append(
        InfoItem(
          label: L10n.string("shutter_speed_label"),
          value: exposureTime
        ))
    }

    if let isoSpeed = exifInfo.isoSpeed {
      items.append(
        InfoItem(
          label: L10n.string("iso_label"),
          value: isoSpeed
        ))
    }

    if let focalLength = exifInfo.focalLength {
      items.append(
        InfoItem(
          label: L10n.string("focal_length_label"),
          value: focalLength
        ))
    }

    if let focalLength35mm = exifInfo.focalLength35mm {
      items.append(
        InfoItem(
          label: L10n.string("focal_length_35mm_label"),
          value: focalLength35mm
        ))
    }

    if let exposureProgram = exifInfo.exposureProgram {
      items.append(
        InfoItem(
          label: L10n.string("exposure_program_label"),
          value: exposureProgram
        ))
    }

    if let meteringMode = exifInfo.meteringMode {
      items.append(
        InfoItem(
          label: L10n.string("metering_mode_label"),
          value: meteringMode
        ))
    }

    if let flash = exifInfo.flash {
      items.append(
        InfoItem(
          label: L10n.string("flash_label"),
          value: flash
        ))
    }

    if let whiteBalance = exifInfo.whiteBalance {
      items.append(
        InfoItem(
          label: L10n.string("white_balance_label"),
          value: whiteBalance
        ))
    }

    return items
  }

  private var locationInfoItems: [InfoItem] {
    var items: [InfoItem] = []

    if let gpsLatitude = exifInfo.gpsLatitude {
      items.append(
        InfoItem(
          label: L10n.string("latitude_label"),
          value: gpsLatitude
        ))
    }

    if let gpsLongitude = exifInfo.gpsLongitude {
      items.append(
        InfoItem(
          label: L10n.string("longitude_label"),
          value: gpsLongitude
        ))
    }

    if let gpsAltitude = exifInfo.gpsAltitude {
      items.append(
        InfoItem(
          label: L10n.string("altitude_label"),
          value: gpsAltitude
        ))
    }

    if let gpsDateTime = exifInfo.gpsDateTime {
      items.append(
        InfoItem(
          label: L10n.string("gps_time_label"),
          value: gpsDateTime
        ))
    }

    return items
  }

  private var technicalInfoItems: [InfoItem] {
    var items: [InfoItem] = []

    if let colorSpace = exifInfo.colorSpace {
      items.append(
        InfoItem(
          label: L10n.string("color_space_label"),
          value: colorSpace
        ))
    }

    if let orientation = exifInfo.orientation {
      items.append(
        InfoItem(
          label: L10n.string("orientation_label"),
          value: orientation
        ))
    }

    if let xResolution = exifInfo.xResolution {
      items.append(
        InfoItem(
          label: L10n.string("x_resolution_label"),
          value: "\(xResolution) \(exifInfo.resolutionUnit ?? "")"
        ))
    }

    if let yResolution = exifInfo.yResolution {
      items.append(
        InfoItem(
          label: L10n.string("y_resolution_label"),
          value: "\(yResolution) \(exifInfo.resolutionUnit ?? "")"
        ))
    }

    return items
  }

  // MARK: - 判断是否有对应数据的计算属性

  private var hasCameraInfo: Bool {
    exifInfo.cameraMake != nil || exifInfo.cameraModel != nil || exifInfo.lensMake != nil
      || exifInfo.lensModel != nil || exifInfo.software != nil
  }

  private var hasShootingParams: Bool {
    exifInfo.fNumber != nil || exifInfo.exposureTime != nil || exifInfo.isoSpeed != nil
      || exifInfo.focalLength != nil || exifInfo.focalLength35mm != nil
      || exifInfo.exposureProgram != nil || exifInfo.meteringMode != nil || exifInfo.flash != nil
      || exifInfo.whiteBalance != nil
  }

  private var hasLocationInfo: Bool {
    exifInfo.gpsLatitude != nil || exifInfo.gpsLongitude != nil || exifInfo.gpsAltitude != nil
      || exifInfo.gpsDateTime != nil
  }

  private var hasTechnicalInfo: Bool {
    exifInfo.colorSpace != nil || exifInfo.orientation != nil || exifInfo.xResolution != nil
      || exifInfo.yResolution != nil
  }
}

// MARK: - 辅助结构和视图

/// 信息项结构体
private struct InfoItem: Identifiable {
  var id: String { label }
  let label: String
  let value: String
}

/// 信息部分视图
private struct InfoSection: View {
  let title: String
  let items: [InfoItem]

  var body: some View {
    if !items.isEmpty {
      VStack(alignment: .leading, spacing: 12) {
        Text(title)
          .font(.headline)
          .foregroundColor(.primary)
          .frame(maxWidth: .infinity, alignment: .leading)

        tableBody
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  private var tableBody: some View {
    VStack(spacing: 0) {
      ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
        InfoRow(label: item.label, value: item.value)

        if index < items.count - 1 {
          Rectangle()
            .fill(Color(nsColor: .separatorColor).opacity(InfoTableLayout.dividerOpacity))
            .frame(height: 0.5)
            .padding(.leading, InfoTableLayout.labelColumnWidth + InfoTableLayout.rowHorizontalPadding)
        }
      }
    }
    .padding(.vertical, 2)
  }
}

/// 信息行视图
private struct InfoRow: View {
  let label: String
  let value: String

  var body: some View {
    HStack(alignment: .firstTextBaseline, spacing: 0) {
      Text(label)
        .font(.system(size: 13, weight: .regular, design: .default))
        .foregroundColor(.secondary)
        .frame(width: InfoTableLayout.labelColumnWidth, alignment: .leading)

      Text(value)
        .font(.system(size: 13, weight: .regular, design: .monospaced))
        .foregroundColor(.primary)
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, 12)
    }
    .padding(.horizontal, InfoTableLayout.rowHorizontalPadding)
    .padding(.vertical, InfoTableLayout.rowVerticalPadding)
  }
}

// MARK: - 预览

#Preview {
  ExifInfoView(
    exifInfo: ExifInfo(
      fileName: "test.jpg",
      filePath: "~/Pictures/test.jpg",
      fileSize: "2.3 MB",
      fileFormat: "JPEG",
      imageWidth: 1920,
      imageHeight: 1080,
      fileModificationDate: "2025年9月6日 下午2:30:45",
      cameraMake: "Canon",
      cameraModel: "EOS R5",
      lensMake: "Canon",
      lensModel: "RF 24-70mm f/2.8L IS USM",
      software: "Adobe Lightroom",
      fNumber: "f/2.8",
      exposureTime: "1/125s",
      isoSpeed: "ISO 400",
      focalLength: "50mm",
      focalLength35mm: "50mm (35mm等效)",
      exposureProgram: "光圈优先",
      meteringMode: "评估测光",
      flash: "未闪光",
      whiteBalance: "自动",
      gpsLatitude: "39.904211° N",
      gpsLongitude: "116.407395° E",
      gpsAltitude: "44.0m 海平面以上",
      gpsDateTime: "2025-09-06 06:30:45 UTC",
      colorSpace: "sRGB",
      orientation: "正常",
      xResolution: "300",
      yResolution: "300",
      resolutionUnit: "英寸"
    )
  )
  .frame(width: 360, height: 520)
  .background(.regularMaterial)
}
