//
//  CropModels.swift
//
//  Lightweight models for crop aspect ratios and state.
//

import Foundation
import CoreGraphics

/// 表示一个固定宽高比（以整数比存储，便于显示与持久化）
struct CropRatio: Codable, Hashable, Identifiable {
  let width: Int
  let height: Int

  var id: String { "\(width):\(height)" }

  /// 以 Double 形式的比例（w/h）
  var value: Double {
    guard width > 0, height > 0 else { return 0 }
    return Double(width) / Double(height)
  }

  var displayName: String { "\(width):\(height)" }
}

/// 预设的裁剪比例
enum CropPreset: CaseIterable, Identifiable {
  case freeform
  case original
  case square_1_1
  case r_3_2
  case r_4_3
  case r_16_9
  case r_9_16

  var id: String { key }

  var key: String {
    switch self {
    case .freeform: return "freeform"
    case .original: return "original"
    case .square_1_1: return "1:1"
    case .r_3_2: return "3:2"
    case .r_4_3: return "4:3"
    case .r_16_9: return "16:9"
    case .r_9_16: return "9:16"
    }
  }

  var titleKey: String {
    switch self {
    case .freeform: return "crop_ratio_freeform"
    case .original: return "crop_ratio_original"
    case .square_1_1: return "crop_ratio_1_1"
    case .r_3_2: return "crop_ratio_3_2"
    case .r_4_3: return "crop_ratio_4_3"
    case .r_16_9: return "crop_ratio_16_9"
    case .r_9_16: return "crop_ratio_9_16"
    }
  }

  /// 如为固定比例，返回对应值；freeform/original 返回 nil（original 由外部根据图片尺寸解析）
  var fixedRatio: CropRatio? {
    switch self {
    case .square_1_1: return CropRatio(width: 1, height: 1)
    case .r_3_2: return CropRatio(width: 3, height: 2)
    case .r_4_3: return CropRatio(width: 4, height: 3)
    case .r_16_9: return CropRatio(width: 16, height: 9)
    case .r_9_16: return CropRatio(width: 9, height: 16)
    default: return nil
    }
  }
}

/// 当前裁剪选项（freeform / original / 固定比例 或 自定义）
enum CropAspectOption: Equatable {
  case freeform
  case original
  case fixed(CropRatio) // 包含预置与自定义

  static func fromPreset(_ preset: CropPreset) -> CropAspectOption {
    switch preset {
    case .freeform: return .freeform
    case .original: return .original
    default:
      if let r = preset.fixedRatio { return .fixed(r) }
      return .freeform
    }
  }
}

/// 计算给定比例下，在目标矩形内的最佳适配裁剪尺寸（最大化覆盖且保持比例）
enum CropMath {
  static func fitRect(in bounds: CGSize, aspect: Double) -> CGSize {
    guard bounds.width > 0, bounds.height > 0, aspect > 0 else { return .zero }
    let bw = bounds.width
    let bh = bounds.height
    let wByH = aspect
    // 首先尝试以宽为主
    var w = bw
    var h = w / wByH
    if h > bh {
      h = bh
      w = h * wByH
    }
    return CGSize(width: w, height: h)
  }
}

