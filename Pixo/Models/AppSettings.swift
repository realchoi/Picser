//
//  AppSettings.swift
//  Pixo
//
//  Created by Eric Cai on 2025/8/19.
//

import AppKit
import Foundation
import SwiftUI

/// 键选择器协议，用于统一不同类型的键选择组件
protocol KeySelectable: RawRepresentable, CaseIterable, Identifiable, Hashable
where RawValue == String {
  var displayName: String { get }
  static func availableKeys() -> [Self]
}

/// 应用设置管理器
class AppSettings: ObservableObject {

  // MARK: - 快捷键设置

  /// 缩放快捷键（UserDefaults 存储）
  @AppStorage("zoomModifierKey") private var zoomModifierKeyStorage: String = ModifierKey.none
    .rawValue
  /// 拖拽快捷键（UserDefaults 存储）
  @AppStorage("panModifierKey") private var panModifierKeyStorage: String = ModifierKey.none
    .rawValue
  /// 图片切换按键（UserDefaults 存储）
  @AppStorage("imageNavigationKey") private var imageNavigationKeyStorage: String =
    ImageNavigationKey.leftRight
    .rawValue
  /// 旋转/镜像 快捷键修饰键（UserDefaults 存储）
  @AppStorage("rotateCCWModifierKey") private var rotateCCWModifierKeyStorage: String = ModifierKey.command.rawValue
  @AppStorage("rotateCWModifierKey") private var rotateCWModifierKeyStorage: String = ModifierKey.command.rawValue
  @AppStorage("mirrorHModifierKey") private var mirrorHModifierKeyStorage: String = ModifierKey.control.rawValue
  @AppStorage("mirrorVModifierKey") private var mirrorVModifierKeyStorage: String = ModifierKey.control.rawValue
  /// 旋转/镜像 快捷键基础键（UserDefaults 存储）
  @AppStorage("rotateCCWBaseKey") private var rotateCCWBaseKeyStorage: String = ShortcutBaseKey.leftBracket.rawValue
  @AppStorage("rotateCWBaseKey") private var rotateCWBaseKeyStorage: String = ShortcutBaseKey.rightBracket.rawValue
  @AppStorage("mirrorHBaseKey") private var mirrorHBaseKeyStorage: String = ShortcutBaseKey.h.rawValue
  @AppStorage("mirrorVBaseKey") private var mirrorVBaseKeyStorage: String = ShortcutBaseKey.v.rawValue
  /// 重置图像变换 快捷键（修饰键 + 基础键）
  @AppStorage("resetTransformModifierKey") private var resetTransformModifierKeyStorage: String = ModifierKey.option.rawValue
  @AppStorage("resetTransformBaseKey") private var resetTransformBaseKeyStorage: String = ShortcutBaseKey.d0.rawValue
  /// 应用语言（UserDefaults 存储）
  @AppStorage("appLanguage") private var appLanguageStorage: String = AppLanguage.system
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
  /// 图片切换按键（UI 显示）
  @Published var imageNavigationKey: ImageNavigationKey = .leftRight {
    didSet {
      imageNavigationKeyStorage = imageNavigationKey.rawValue
    }
  }
  /// 旋转/镜像 快捷键修饰键（UI 显示）
  @Published var rotateCCWModifierKey: ModifierKey = .command {
    didSet { rotateCCWModifierKeyStorage = rotateCCWModifierKey.rawValue }
  }
  @Published var rotateCWModifierKey: ModifierKey = .command {
    didSet { rotateCWModifierKeyStorage = rotateCWModifierKey.rawValue }
  }
  @Published var mirrorHModifierKey: ModifierKey = .control {
    didSet { mirrorHModifierKeyStorage = mirrorHModifierKey.rawValue }
  }
  @Published var mirrorVModifierKey: ModifierKey = .control {
    didSet { mirrorVModifierKeyStorage = mirrorVModifierKey.rawValue }
  }
  @Published var resetTransformModifierKey: ModifierKey = .option {
    didSet { resetTransformModifierKeyStorage = resetTransformModifierKey.rawValue }
  }
  /// 旋转/镜像 快捷键基础键（UI 显示）
  @Published var rotateCCWBaseKey: ShortcutBaseKey = .leftBracket {
    didSet { rotateCCWBaseKeyStorage = rotateCCWBaseKey.rawValue }
  }
  @Published var rotateCWBaseKey: ShortcutBaseKey = .rightBracket {
    didSet { rotateCWBaseKeyStorage = rotateCWBaseKey.rawValue }
  }
  @Published var mirrorHBaseKey: ShortcutBaseKey = .h {
    didSet { mirrorHBaseKeyStorage = mirrorHBaseKey.rawValue }
  }
  @Published var mirrorVBaseKey: ShortcutBaseKey = .v {
    didSet { mirrorVBaseKeyStorage = mirrorVBaseKey.rawValue }
  }
  @Published var resetTransformBaseKey: ShortcutBaseKey = .d0 {
    didSet { resetTransformBaseKeyStorage = resetTransformBaseKey.rawValue }
  }
  /// 应用语言（UI 显示）
  @Published var appLanguage: AppLanguage = .system {
    didSet {
      appLanguageStorage = appLanguage.rawValue
      // 更新本地化管理器的语言设置
      LocalizationManager.shared.setLanguage(appLanguage.rawValue)
    }
  }

  // MARK: - 显示设置

  /// 缩放灵敏度（UserDefaults 存储）
  @AppStorage("zoomSensitivity") var zoomSensitivity: Double = 0.05 {
    didSet {
      // 约束到有效范围 0.01...0.1
      if zoomSensitivity < 0.01 { zoomSensitivity = 0.01 }
      if zoomSensitivity > 0.1 { zoomSensitivity = 0.1 }
    }
  }
  /// 最小缩放比例（UserDefaults 存储）
  @AppStorage("minZoomScale") var minZoomScale: Double = 0.1 {
    didSet {
      // 合理边界，并保持小于最大值
      if minZoomScale <= 0 { minZoomScale = 0.1 }
      if minZoomScale >= maxZoomScale { minZoomScale = max(0.1, maxZoomScale - 0.1) }
    }
  }
  /// 最大缩放比例（UserDefaults 存储）
  @AppStorage("maxZoomScale") var maxZoomScale: Double = 10.0 {
    didSet {
      // 必须大于最小值
      if maxZoomScale <= minZoomScale { maxZoomScale = minZoomScale + 0.1 }
    }
  }

  // MARK: - 小地图设置

  /// 是否显示右下角小地图（UserDefaults 存储）
  @AppStorage("showMinimap") var showMinimap: Bool = true

  /// 小地图自动隐藏时间（秒，0 表示不自动隐藏）（UserDefaults 存储）
  @AppStorage("minimapAutoHideSeconds") var minimapAutoHideSeconds: Double = 0.0 {
    didSet {
      // 约束范围 0...10 秒
      if minimapAutoHideSeconds < 0 { minimapAutoHideSeconds = 0 }
      if minimapAutoHideSeconds > 10 { minimapAutoHideSeconds = 10 }
    }
  }

  // MARK: - 裁剪设置

  /// 自定义裁剪比例（持久化 JSON）
  @AppStorage("customCropRatiosJSON") private var customCropRatiosJSON: String = "[]"
  /// 自定义裁剪比例（UI 显示）
  @Published var customCropRatios: [CropRatio] = [] {
    didSet { saveCustomCropRatios() }
  }

  // MARK: - 初始化

  init() {
    // 从 UserDefaults 加载保存的修饰键值
    self.zoomModifierKey = ModifierKey(rawValue: zoomModifierKeyStorage) ?? .none
    self.panModifierKey = ModifierKey(rawValue: panModifierKeyStorage) ?? .none
    self.imageNavigationKey = ImageNavigationKey(rawValue: imageNavigationKeyStorage) ?? .leftRight
    self.appLanguage = AppLanguage(rawValue: appLanguageStorage) ?? .system
    self.rotateCCWModifierKey = ModifierKey(rawValue: rotateCCWModifierKeyStorage) ?? .command
    self.rotateCWModifierKey = ModifierKey(rawValue: rotateCWModifierKeyStorage) ?? .command
    self.mirrorHModifierKey = ModifierKey(rawValue: mirrorHModifierKeyStorage) ?? .control
    self.mirrorVModifierKey = ModifierKey(rawValue: mirrorVModifierKeyStorage) ?? .control
    self.resetTransformModifierKey = ModifierKey(rawValue: resetTransformModifierKeyStorage) ?? .option
    self.rotateCCWBaseKey = ShortcutBaseKey(rawValue: rotateCCWBaseKeyStorage) ?? .leftBracket
    self.rotateCWBaseKey = ShortcutBaseKey(rawValue: rotateCWBaseKeyStorage) ?? .rightBracket
    self.mirrorHBaseKey = ShortcutBaseKey(rawValue: mirrorHBaseKeyStorage) ?? .h
    self.mirrorVBaseKey = ShortcutBaseKey(rawValue: mirrorVBaseKeyStorage) ?? .v
    self.resetTransformBaseKey = ShortcutBaseKey(rawValue: resetTransformBaseKeyStorage) ?? .d0

    // 初始化时同步语言设置到本地化管理器
    LocalizationManager.shared.setLanguage(self.appLanguage.rawValue)

    // 加载自定义裁剪比例
    loadCustomCropRatios()
  }

  // MARK: - 公共方法

  /// 验证设置的有效性
  func validateSettings() -> [String] {
    var errors: [String] = []

    if zoomSensitivity <= 0 || zoomSensitivity > 0.1 {
      errors.append("zoom_sensitivity_range_error".localized)
    }

    if minZoomScale <= 0 || minZoomScale >= maxZoomScale {
      errors.append("min_zoom_scale_invalid_error".localized)
    }

    if maxZoomScale <= minZoomScale {
      errors.append("max_zoom_scale_invalid_error".localized)
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

  /// 重置所有设置为默认值
  func resetToDefaults(settingsTab: SettingsTab) {
    switch settingsTab {
    case .general:
      appLanguage = .system
    case .keyboard:
      zoomModifierKey = .none
      panModifierKey = .none
      imageNavigationKey = .leftRight
      rotateCCWModifierKey = .command
      rotateCWModifierKey = .command
      mirrorHModifierKey = .control
      mirrorVModifierKey = .control
      rotateCCWBaseKey = .leftBracket
      rotateCWBaseKey = .rightBracket
      mirrorHBaseKey = .h
      mirrorVBaseKey = .v
      resetTransformModifierKey = .option
      resetTransformBaseKey = .d0
    case .display:
      zoomSensitivity = 0.05
      minZoomScale = 0.1
      maxZoomScale = 10.0
      showMinimap = true
      minimapAutoHideSeconds = 0.0
    case .cache:
      break
    }
  }

  // MARK: - 裁剪设置持久化
  private func loadCustomCropRatios() {
    guard let data = customCropRatiosJSON.data(using: .utf8) else {
      customCropRatios = []
      return
    }
    if let arr = try? JSONDecoder().decode([CropRatio].self, from: data) {
      customCropRatios = arr
    } else {
      customCropRatios = []
    }
  }

  private func saveCustomCropRatios() {
    if let data = try? JSONEncoder().encode(customCropRatios),
       let str = String(data: data, encoding: .utf8) {
      customCropRatiosJSON = str
    }
  }
}

/// 设置标签枚举，用于设置页面标签
enum SettingsTab: String, CaseIterable, Identifiable {
  case general = "General"
  case keyboard = "Keyboard"
  case display = "Display"
  case cache = "Cache"

  var id: String { rawValue }
}

/// 定义修饰键枚举，用于快捷键设置
enum ModifierKey: String, CaseIterable, Identifiable, Hashable, KeySelectable {
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
      return "modifier_none".localized
    case .command:
      return "modifier_command".localized
    case .option:
      return "modifier_option".localized
    case .control:
      return "modifier_control".localized
    case .shift:
      return "modifier_shift".localized
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
    return [.none, .control, .command, .option, .shift]
  }
}

/// 定义应用语言枚举，用于语言选择设置
enum AppLanguage: String, CaseIterable, Identifiable, Hashable, KeySelectable {
  case system = "system"
  case chinese = "chinese"
  case english = "english"

  var id: String { rawValue }

  /// 语言显示名称
  var displayName: String {
    switch self {
    case .system:
      return "language_system".localized
    case .chinese:
      return "language_chinese".localized
    case .english:
      return "language_english".localized
    }
  }

  /// 语言的 Locale 标识符
  var localeIdentifier: String? {
    switch self {
    case .system:
      return nil  // 跟随系统
    case .chinese:
      return "zh-Hans"
    case .english:
      return "en"
    }
  }

  /// 返回用户可选择的语言选项
  static func availableKeys() -> [AppLanguage] {
    return [.system, .chinese, .english]
  }
}

/// 定义图片切换按键枚举，用于图片导航设置
enum ImageNavigationKey: String, CaseIterable, Identifiable, Hashable, KeySelectable {
  case leftRight = "leftRight"  // 左右方向键（默认）
  case upDown = "upDown"  // 上下方向键
  case pageUpDown = "pageUpDown"  // PageUp/PageDown

  var id: String { rawValue }

  /// 图片切换按键显示名称
  var displayName: String {
    switch self {
    case .leftRight:
      return "navigation_left_right".localized
    case .upDown:
      return "navigation_up_down".localized
    case .pageUpDown:
      return "navigation_page_up_down".localized
    }
  }

  /// 返回用户可选择的图片切换按键选项
  static func availableKeys() -> [ImageNavigationKey] {
    return [.leftRight, .upDown, .pageUpDown]
  }
}

/// 变换动作的基础键选择（字母/数字/常用符号）
enum ShortcutBaseKey: String, CaseIterable, Identifiable, Hashable, KeySelectable {
  // 常用符号
  case leftBracket = "["
  case rightBracket = "]"
  case minus = "-"
  case equal = "="
  case semicolon = ";"
  case quote = "'"
  case comma = ","
  case period = "."
  case slash = "/"

  // 字母（仅列出常用 + 备选）
  case h = "h"
  case v = "v"
  case r = "r"
  case l = "l"
  case f = "f"
  case m = "m"
  case a = "a"
  case b = "b"
  case c = "c"
  case d = "d"
  case e = "e"
  case g = "g"
  case i = "i"
  case j = "j"
  case k = "k"
  case n = "n"
  case o = "o"
  case p = "p"
  case q = "q"
  case s = "s"
  case t = "t"
  case u = "u"
  case w = "w"
  case x = "x"
  case y = "y"
  case z = "z"

  // 数字
  case d0 = "0"
  case d1 = "1"
  case d2 = "2"
  case d3 = "3"
  case d4 = "4"
  case d5 = "5"
  case d6 = "6"
  case d7 = "7"
  case d8 = "8"
  case d9 = "9"

  var id: String { rawValue }

  var displayName: String {
    // 直接显示字符；字母转大写增强辨识度
    if let ch = rawValue.first, ch.isLetter {
      return String(ch).uppercased()
    }
    return rawValue
  }

  static func availableKeys() -> [ShortcutBaseKey] {
    // 合理排序：符号 -> 字母 -> 数字
    return [
      .leftBracket, .rightBracket, .minus, .equal, .semicolon, .quote, .comma, .period, .slash,
      .h, .v, .r, .l, .f, .m, .a, .b, .c, .d, .e, .g, .i, .j, .k, .n, .o, .p, .q, .s, .t, .u, .w, .x, .y, .z,
      .d0, .d1, .d2, .d3, .d4, .d5, .d6, .d7, .d8, .d9,
    ]
  }

  /// 对应 SwiftUI 的 KeyEquivalent
  var keyEquivalent: KeyEquivalent {
    let ch = Character(rawValue)
    return KeyEquivalent(ch)
  }
}
