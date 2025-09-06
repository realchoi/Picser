//
//  ExifInfoView.swift
//  PicTube
//
//  Created by Eric Cai on 2025/09/06.
//

import SwiftUI

/// EXIF 信息展示视图
struct ExifInfoView: View {
  let exifInfo: ExifInfo
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    VStack(spacing: 0) {
      // 标题栏
      HStack {
        Text(NSLocalizedString("exif_window_title", comment: "Image Information"))
          .font(.headline)
          .foregroundColor(.primary)

        Spacer()

        Button(NSLocalizedString("close_button", comment: "Close")) {
          dismiss()
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.small)
      }
      .padding()
      .background(.regularMaterial)

      Divider()

      // 内容区域
      ScrollView(.vertical, showsIndicators: true) {
        LazyVStack(alignment: .leading, spacing: 20, pinnedViews: []) {
          // 基本信息部分
          InfoSection(
            title: NSLocalizedString("basic_info_section", comment: "Basic Information"),
            items: basicInfoItems
          )

          // 相机信息部分（只在有相机数据时显示）
          if hasCameraInfo {
            InfoSection(
              title: NSLocalizedString("camera_info_section", comment: "Camera Information"),
              items: cameraInfoItems
            )
          }

          // 拍摄参数部分（只在有拍摄数据时显示）
          if hasShootingParams {
            InfoSection(
              title: NSLocalizedString("shooting_params_section", comment: "Shooting Parameters"),
              items: shootingParamItems
            )
          }

          // 位置信息部分（只在有GPS数据时显示）
          if hasLocationInfo {
            InfoSection(
              title: NSLocalizedString("location_info_section", comment: "Location Information"),
              items: locationInfoItems
            )
          }

          // 技术信息部分（只在有技术数据时显示）
          if hasTechnicalInfo {
            InfoSection(
              title: NSLocalizedString("technical_info_section", comment: "Technical Information"),
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
    .frame(width: 600, height: 500)
    .background(.regularMaterial)
  }

  // MARK: - 计算属性

  private var basicInfoItems: [InfoItem] {
    [
      InfoItem(
        label: NSLocalizedString("file_name_label", comment: "File Name"),
        value: exifInfo.fileName
      ),
      InfoItem(
        label: NSLocalizedString("file_size_label", comment: "File Size"),
        value: exifInfo.fileSize
      ),
      InfoItem(
        label: NSLocalizedString("file_format_label", comment: "File Format"),
        value: exifInfo.fileFormat
      ),
      InfoItem(
        label: NSLocalizedString("image_dimensions_label", comment: "Image Dimensions"),
        value: "\(exifInfo.imageWidth) × \(exifInfo.imageHeight)"
      ),
      InfoItem(
        label: NSLocalizedString("modification_date_label", comment: "Modification Date"),
        value: exifInfo.fileModificationDate
      ),
    ]
  }

  private var cameraInfoItems: [InfoItem] {
    var items: [InfoItem] = []

    if let cameraMake = exifInfo.cameraMake {
      items.append(
        InfoItem(
          label: NSLocalizedString("camera_make_label", comment: "Camera Make"),
          value: cameraMake
        ))
    }

    if let cameraModel = exifInfo.cameraModel {
      items.append(
        InfoItem(
          label: NSLocalizedString("camera_model_label", comment: "Camera Model"),
          value: cameraModel
        ))
    }

    if let lensMake = exifInfo.lensMake {
      items.append(
        InfoItem(
          label: NSLocalizedString("lens_make_label", comment: "Lens Make"),
          value: lensMake
        ))
    }

    if let lensModel = exifInfo.lensModel {
      items.append(
        InfoItem(
          label: NSLocalizedString("lens_model_label", comment: "Lens Model"),
          value: lensModel
        ))
    }

    if let software = exifInfo.software {
      items.append(
        InfoItem(
          label: NSLocalizedString("software_label", comment: "Software"),
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
          label: NSLocalizedString("aperture_label", comment: "Aperture"),
          value: fNumber
        ))
    }

    if let exposureTime = exifInfo.exposureTime {
      items.append(
        InfoItem(
          label: NSLocalizedString("shutter_speed_label", comment: "Shutter Speed"),
          value: exposureTime
        ))
    }

    if let isoSpeed = exifInfo.isoSpeed {
      items.append(
        InfoItem(
          label: NSLocalizedString("iso_label", comment: "ISO Speed"),
          value: isoSpeed
        ))
    }

    if let focalLength = exifInfo.focalLength {
      items.append(
        InfoItem(
          label: NSLocalizedString("focal_length_label", comment: "Focal Length"),
          value: focalLength
        ))
    }

    if let focalLength35mm = exifInfo.focalLength35mm {
      items.append(
        InfoItem(
          label: NSLocalizedString("focal_length_35mm_label", comment: "35mm Equivalent"),
          value: focalLength35mm
        ))
    }

    if let exposureProgram = exifInfo.exposureProgram {
      items.append(
        InfoItem(
          label: NSLocalizedString("exposure_program_label", comment: "Exposure Program"),
          value: exposureProgram
        ))
    }

    if let meteringMode = exifInfo.meteringMode {
      items.append(
        InfoItem(
          label: NSLocalizedString("metering_mode_label", comment: "Metering Mode"),
          value: meteringMode
        ))
    }

    if let flash = exifInfo.flash {
      items.append(
        InfoItem(
          label: NSLocalizedString("flash_label", comment: "Flash"),
          value: flash
        ))
    }

    if let whiteBalance = exifInfo.whiteBalance {
      items.append(
        InfoItem(
          label: NSLocalizedString("white_balance_label", comment: "White Balance"),
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
          label: NSLocalizedString("latitude_label", comment: "Latitude"),
          value: gpsLatitude
        ))
    }

    if let gpsLongitude = exifInfo.gpsLongitude {
      items.append(
        InfoItem(
          label: NSLocalizedString("longitude_label", comment: "Longitude"),
          value: gpsLongitude
        ))
    }

    if let gpsAltitude = exifInfo.gpsAltitude {
      items.append(
        InfoItem(
          label: NSLocalizedString("altitude_label", comment: "Altitude"),
          value: gpsAltitude
        ))
    }

    if let gpsDateTime = exifInfo.gpsDateTime {
      items.append(
        InfoItem(
          label: NSLocalizedString("gps_time_label", comment: "GPS Time"),
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
          label: NSLocalizedString("color_space_label", comment: "Color Space"),
          value: colorSpace
        ))
    }

    if let orientation = exifInfo.orientation {
      items.append(
        InfoItem(
          label: NSLocalizedString("orientation_label", comment: "Orientation"),
          value: orientation
        ))
    }

    if let xResolution = exifInfo.xResolution {
      items.append(
        InfoItem(
          label: NSLocalizedString("x_resolution_label", comment: "Horizontal Resolution"),
          value: "\(xResolution) \(exifInfo.resolutionUnit ?? "")"
        ))
    }

    if let yResolution = exifInfo.yResolution {
      items.append(
        InfoItem(
          label: NSLocalizedString("y_resolution_label", comment: "Vertical Resolution"),
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
private struct InfoItem {
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

        VStack(alignment: .leading, spacing: 8) {
          ForEach(items, id: \.label) { item in
            InfoRow(label: item.label, value: item.value)
          }
        }
        .padding(.leading, 8)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
  }
}

/// 信息行视图
private struct InfoRow: View {
  let label: String
  let value: String

  var body: some View {
    HStack(alignment: .top, spacing: 0) {
      // 标签部分 - 固定宽度
      Text(label)
        .font(.system(.body, design: .default))
        .foregroundColor(.secondary)
        .frame(width: 150, alignment: .leading)

      // 值部分 - 使用剩余空间
      Text(value)
        .font(.system(.body, design: .monospaced))
        .foregroundColor(.primary)
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, 12)
    }
    .padding(.horizontal, 4)
  }
}

// MARK: - 预览

#Preview {
  ExifInfoView(
    exifInfo: ExifInfo(
      fileName: "test.jpg",
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
}
