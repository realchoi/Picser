//
//  AppSettings.swift
//  PicTube
//
//  Created by Eric Cai on 2025/8/19.
//

import Foundation
import SwiftUI

// 定义修饰键枚举
enum ModifierKey: String, CaseIterable, Identifiable {
  case none = "none"
  case command = "command"
  case option = "option"
  case control = "control"
  case shift = "shift"

  var id: String { rawValue }

  // 显示名称
  var displayName: String {
    switch self {
    case .none:
      return NSLocalizedString("modifier_none", comment: "None modifier key")
    case .command:
      return NSLocalizedString("modifier_command", comment: "Command modifier key")
    case .option:
      return NSLocalizedString("modifier_option", comment: "Option modifier key")
    case .control:
      return NSLocalizedString("modifier_control", comment: "Control modifier key")
    case .shift:
      return NSLocalizedString("modifier_shift", comment: "Shift modifier key")
    }
  }

  // 转换为 NSEvent.ModifierFlags
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

  // 返回用户可选择的修饰键选项
  static func availableKeys() -> [ModifierKey] {
    return [.none, .control, .command, .option]
  }
}

// 应用设置管理器
class AppSettings: ObservableObject {

  // MARK: - 快捷键设置

  @AppStorage("zoomModifierKey") private var zoomModifierKeyStorage: String = ModifierKey.control
    .rawValue
  @AppStorage("panModifierKey") private var panModifierKeyStorage: String = ModifierKey.none
    .rawValue

  // 缩放快捷键
  @Published var zoomModifierKey: ModifierKey = .control {
    didSet {
      zoomModifierKeyStorage = zoomModifierKey.rawValue
    }
  }

  // 拖拽快捷键
  @Published var panModifierKey: ModifierKey = .none {
    didSet {
      panModifierKeyStorage = panModifierKey.rawValue
    }
  }

  // MARK: - 显示设置

  @AppStorage("defaultZoomScale") var defaultZoomScale: Double = 1.0
  @AppStorage("zoomSensitivity") var zoomSensitivity: Double = 0.1
  @AppStorage("minZoomScale") var minZoomScale: Double = 0.5
  @AppStorage("maxZoomScale") var maxZoomScale: Double = 10.0

  // MARK: - 行为设置

  @AppStorage("resetZoomOnImageChange") var resetZoomOnImageChange: Bool = true
  @AppStorage("resetPanOnImageChange") var resetPanOnImageChange: Bool = true

  // MARK: - 初始化

  init() {
    // 从 UserDefaults 加载保存的值
    self.zoomModifierKey = ModifierKey(rawValue: zoomModifierKeyStorage) ?? .control
    self.panModifierKey = ModifierKey(rawValue: panModifierKeyStorage) ?? .none
  }

  // MARK: - 公共方法

  // 重置所有设置到默认值
  func resetToDefaults() {
    zoomModifierKey = .control
    panModifierKey = .none
    defaultZoomScale = 1.0
    zoomSensitivity = 0.1
    minZoomScale = 0.5
    maxZoomScale = 10.0
    resetZoomOnImageChange = true
    resetPanOnImageChange = true
  }

  // 验证设置的有效性
  func validateSettings() -> [String] {
    var errors: [String] = []

    if zoomSensitivity <= 0 || zoomSensitivity > 1.0 {
      errors.append("缩放灵敏度必须在 0.1 到 1.0 之间")
    }

    if minZoomScale <= 0 || minZoomScale >= maxZoomScale {
      errors.append("最小缩放比例必须大于 0 且小于最大缩放比例")
    }

    if maxZoomScale <= minZoomScale {
      errors.append("最大缩放比例必须大于最小缩放比例")
    }

    if defaultZoomScale < minZoomScale || defaultZoomScale > maxZoomScale {
      errors.append("默认缩放比例必须在最小和最大缩放比例之间")
    }

    return errors
  }

  // 检查快捷键是否匹配指定的修饰键
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
