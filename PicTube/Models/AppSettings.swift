//
//  AppSettings.swift
//  PicTube
//
//  Created by Eric Cai on 2025/8/19.
//

import Foundation
import SwiftUI

/// 应用设置管理器
class AppSettings: ObservableObject {

  // MARK: - 快捷键设置

  /// 缩放快捷键（UserDefaults 存储）
  @AppStorage("zoomModifierKey") private var zoomModifierKeyStorage: String = ModifierKey.none
    .rawValue
  /// 拖拽快捷键（UserDefaults 存储）
  @AppStorage("panModifierKey") private var panModifierKeyStorage: String = ModifierKey.none
    .rawValue

  /// 缩放快捷键（UI 显示）
  @Published var zoomModifierKey: ModifierKey = .none {
    didSet {
      zoomModifierKeyStorage = zoomModifierKey.rawValue
    }
  }
  /// 拖拽快捷键（UI 显示）
  @Published var panModifierKey: ModifierKey = .none {
    didSet {
      panModifierKeyStorage = panModifierKey.rawValue
    }
  }

  // MARK: - 显示设置

  /// 缩放灵敏度（UserDefaults 存储）
  @AppStorage("zoomSensitivity") var zoomSensitivity: Double = 0.01
  /// 最小缩放比例（UserDefaults 存储）
  @AppStorage("minZoomScale") var minZoomScale: Double = 0.5
  /// 最大缩放比例（UserDefaults 存储）
  @AppStorage("maxZoomScale") var maxZoomScale: Double = 10.0

  // MARK: - 行为设置

  /// 图片切换时是否重置缩放（UserDefaults 存储）
  @AppStorage("resetZoomOnImageChange") var resetZoomOnImageChange: Bool = true
  /// 图片切换时是否重置拖拽（UserDefaults 存储）
  @AppStorage("resetPanOnImageChange") var resetPanOnImageChange: Bool = true

  // MARK: - 初始化

  init() {
    // 从 UserDefaults 加载保存的修饰键值
    self.zoomModifierKey = ModifierKey(rawValue: zoomModifierKeyStorage) ?? .none
    self.panModifierKey = ModifierKey(rawValue: panModifierKeyStorage) ?? .none
  }

  // MARK: - 公共方法

  /// 验证设置的有效性
  func validateSettings() -> [String] {
    var errors: [String] = []

    if zoomSensitivity <= 0 || zoomSensitivity > 0.1 {
      errors.append("缩放灵敏度必须在 0.01 到 0.1 之间")
    }

    if minZoomScale <= 0 || minZoomScale >= maxZoomScale {
      errors.append("最小缩放比例必须大于 0 且小于最大缩放比例")
    }

    if maxZoomScale <= minZoomScale {
      errors.append("最大缩放比例必须大于最小缩放比例")
    }

    return errors
  }

  /// 检查快捷键是否匹配指定的修饰键
  func isModifierKeyPressed(_ modifierFlags: NSEvent.ModifierFlags, for keyType: ModifierKey)
    -> Bool
  {
    let targetFlags = keyType.nsEventModifierFlags

    if keyType == .none {
      // 如果设置为"无"，则检查是否没有按下任何修饰键
      return modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty
    } else {
      // 检查是否按下了指定的修饰键
      return modifierFlags.contains(targetFlags)
    }
  }
}

/// 定义修饰键枚举，用于快捷键设置
enum ModifierKey: String, CaseIterable, Identifiable {
  case none = "none"
  case command = "command"
  case option = "option"
  case control = "control"
  case shift = "shift"

  var id: String { rawValue }

  /// 修饰键显示名称
  var displayName: String {
    switch self {
    case .none:
      return NSLocalizedString("modifier_none", comment: "无修饰键")
    case .command:
      return NSLocalizedString("modifier_command", comment: "Command(⌘)")
    case .option:
      return NSLocalizedString("modifier_option", comment: "Option(⌥)")
    case .control:
      return NSLocalizedString("modifier_control", comment: "Control(⌃)")
    case .shift:
      return NSLocalizedString("modifier_shift", comment: "Shift(⇧)")
    }
  }

  /// 转换为 NSEvent.ModifierFlags
  var nsEventModifierFlags: NSEvent.ModifierFlags {
    switch self {
    case .none:
      return []
    case .command:
      return .command
    case .option:
      return .option
    case .control:
      return .control
    case .shift:
      return .shift
    }
  }

  /// 返回用户可选择的修饰键选项
  static func availableKeys() -> [ModifierKey] {
    return [.none, .control, .command, .option]
  }
}
