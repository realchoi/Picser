//
//  AppSettings.swift
//
//  Created by Eric Cai on 2025/8/19.
//

import AppKit
import Foundation
import SwiftUI
import KeyboardShortcuts

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
  /// 应用语言（UserDefaults 存储）
  @AppStorage("appLanguage") private var appLanguageStorage: String = AppLanguage.system
    .rawValue
  /// 删除确认开关（UserDefaults 存储）
  @AppStorage("deleteConfirmationEnabled") private var deleteConfirmationEnabledStorage: Bool = true
  /// 删除快捷键偏好（UserDefaults 存储）
  @AppStorage("deleteShortcutPreference") private var deleteShortcutPreferenceStorage: String =
    DeleteShortcutPreference.both.rawValue

  /// KeyboardShortcuts 动作注册表，集中管理所有可配置快捷键。
  private let shortcutCatalog = KeyboardShortcutCatalog.shared

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
  private var isApplyingNavigationOption = false
  private var isApplyingDeletePreference = false

  /// 图片导航快捷键选项（UI 显示）
  @Published var imageNavigationOption: NavigationShortcutOption = .leftRight {
    didSet {
      guard oldValue != imageNavigationOption else { return }
      guard !isApplyingNavigationOption else { return }
      if !applyNavigationShortcuts(option: imageNavigationOption) {
        isApplyingNavigationOption = true
        imageNavigationOption = oldValue
        isApplyingNavigationOption = false
      }
    }
  }
  /// 应用语言（UI 显示）
  @Published var appLanguage: AppLanguage = .system {
    didSet {
      appLanguageStorage = appLanguage.rawValue
      // 更新本地化管理器的语言设置
      LocalizationManager.shared.setLanguage(appLanguage.rawValue)
    }
  }
  /// 删除操作是否需要弹窗确认（UI 显示）
  @Published var deleteConfirmationEnabled: Bool = true {
    didSet { deleteConfirmationEnabledStorage = deleteConfirmationEnabled }
  }
  /// 删除快捷键偏好设置
  @Published var deleteShortcutPreference: DeleteShortcutPreference = .both {
    didSet {
      guard oldValue != deleteShortcutPreference else { return }
      guard !isApplyingDeletePreference else { return }
      if applyDeleteShortcutPreference(deleteShortcutPreference) {
        deleteShortcutPreferenceStorage = deleteShortcutPreference.rawValue
      } else {
        isApplyingDeletePreference = true
        deleteShortcutPreference = oldValue
        isApplyingDeletePreference = false
      }
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
  /// 是否围绕指针进行缩放（UserDefaults 存储）
  @AppStorage("zoomAnchorsToPointer") private var zoomAnchorsToPointerStorage: Bool = true {
    willSet {
      guard zoomAnchorsToPointerStorage != newValue else { return }
      objectWillChange.send()
    }
  }
  var zoomAnchorsToPointer: Bool {
    get { zoomAnchorsToPointerStorage }
    set { zoomAnchorsToPointerStorage = newValue }
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

  // MARK: - 图片枚举设置

  /// 是否递归扫描子目录寻找图片（UserDefaults 存储）
  @AppStorage("imageScanRecursively") var imageScanRecursively: Bool = true

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
    AppSettings.migrateLegacyShortcuts()
    self.zoomModifierKey = ModifierKey(rawValue: zoomModifierKeyStorage) ?? .none
    self.panModifierKey = ModifierKey(rawValue: panModifierKeyStorage) ?? .none
    self.imageNavigationOption = NavigationShortcutOption.fromCurrentShortcuts(
      previous: KeyboardShortcuts.getShortcut(for: .navigatePrevious),
      next: KeyboardShortcuts.getShortcut(for: .navigateNext)
    )
    self.appLanguage = AppLanguage(rawValue: appLanguageStorage) ?? .system
    self.deleteConfirmationEnabled = deleteConfirmationEnabledStorage
    self.deleteShortcutPreference =
      DeleteShortcutPreference(rawValue: deleteShortcutPreferenceStorage) ?? .both

    // 初始化时同步语言设置到本地化管理器
    LocalizationManager.shared.setLanguage(self.appLanguage.rawValue)

    // 加载自定义裁剪比例
    loadCustomCropRatios()
    deactivateAllShortcuts()
  }

  // MARK: - 公共方法

  /// 验证设置的有效性
  func validateSettings() -> [String] {
    var errors: [String] = []

    if zoomSensitivity <= 0 || zoomSensitivity > 0.1 {
      errors.append(L10n.string("zoom_sensitivity_range_error"))
    }

    if minZoomScale <= 0 || minZoomScale >= maxZoomScale {
      errors.append(L10n.string("min_zoom_scale_invalid_error"))
    }

    if maxZoomScale <= minZoomScale {
      errors.append(L10n.string("max_zoom_scale_invalid_error"))
    }

    return errors
  }

  /// 获取指定动作当前生效的快捷键，若用户未自定义则回落到默认值。
  /// - Parameter action: 业务动作枚举值。
  /// - Returns: 当前生效的快捷键，若无快捷键则返回 nil。
  func shortcut(for action: ShortcutAction) -> KeyboardShortcuts.Shortcut? {
    guard let definition = shortcutCatalog.definition(for: action) else { return nil }
    return KeyboardShortcuts.getShortcut(for: definition.name)
  }

  enum ShortcutRecorderHandlingResult {
    case accepted
    case conflict(ShortcutAction)
  }

  /// 录制器回调触发时禁用全局监听并处理应用内冲突。
  @discardableResult
  func handleRecorderChange(
    for action: ShortcutAction,
    newShortcut: KeyboardShortcuts.Shortcut?,
    previousShortcut: KeyboardShortcuts.Shortcut?
  ) -> ShortcutRecorderHandlingResult {
    guard let definition = shortcutCatalog.definition(for: action) else {
      return .accepted
    }

    // 快捷键未变化时直接退出
    if newShortcut == previousShortcut {
      deactivateShortcut(for: action)
      return .accepted
    }

    if let updatedShortcut = newShortcut,
       let conflictAction = findAppLevelConflict(for: updatedShortcut, excluding: action)
    {
      restoreShortcut(previousShortcut, for: definition.name)
      deactivateShortcut(for: action)
      presentConflictAlert(conflictingAction: conflictAction, shortcut: updatedShortcut)
      return .conflict(conflictAction)
    }

    deactivateShortcut(for: action)
    if action == .navigatePrevious || action == .navigateNext {
      imageNavigationOption = NavigationShortcutOption.fromCurrentShortcuts(
        previous: KeyboardShortcuts.getShortcut(for: .navigatePrevious),
        next: KeyboardShortcuts.getShortcut(for: .navigateNext)
      )
    }
    return .accepted
  }

  /// 将所有可配置快捷键恢复到默认状态。
  func resetKeyboardShortcutsToDefaults() {
    objectWillChange.send()
    for action in ShortcutAction.allCases {
      guard let definition = shortcutCatalog.definition(for: action) else { continue }
      KeyboardShortcuts.reset(definition.name)
    }
    imageNavigationOption = .leftRight
    deleteShortcutPreference = .both
    deactivateAllShortcuts()
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
      deleteConfirmationEnabled = true
    case .keyboard:
      zoomModifierKey = .none
      panModifierKey = .none
      resetKeyboardShortcutsToDefaults()
    case .display:
      zoomSensitivity = 0.05
      zoomAnchorsToPointer = true
      minZoomScale = 0.1
      maxZoomScale = 10.0
      showMinimap = true
      minimapAutoHideSeconds = 0.0
      imageScanRecursively = true
    case .cache:
      break
    case .about:
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
  case about = "About"

  var id: String { rawValue }
}

/// 导航快捷键选项，覆盖应用支持的固定组合。
enum NavigationShortcutOption: String, CaseIterable, Identifiable {
  case leftRight
  case upDown
  case pageUpDown
  case custom

  var id: String { rawValue }

  /// 对应本地化 key。
  var localizedTitleKey: String {
    switch self {
    case .leftRight:
      return "navigation_left_right"
    case .upDown:
      return "navigation_up_down"
    case .pageUpDown:
      return "navigation_page_up_down"
    case .custom:
      return "navigation_custom_option_label"
    }
  }

  static func fromCurrentShortcuts(
    previous: KeyboardShortcuts.Shortcut?,
    next: KeyboardShortcuts.Shortcut?
  ) -> NavigationShortcutOption {
    if previous?.matches(key: .leftArrow, modifiers: []) == true,
       next?.matches(key: .rightArrow, modifiers: []) == true {
      return .leftRight
    }
    if previous?.matches(key: .upArrow, modifiers: []) == true,
       next?.matches(key: .downArrow, modifiers: []) == true {
      return .upDown
    }
    if previous?.matches(key: .pageUp, modifiers: []) == true,
       next?.matches(key: .pageDown, modifiers: []) == true {
      return .pageUpDown
    }
    return .custom
  }
}

/// 删除快捷键选择项，提供预设组合
enum DeleteShortcutPreference: String, CaseIterable, Identifiable {
  case both
  case backspace
  case forwardDelete
  case none

  var id: String { rawValue }

  /// Picker 文案对应的本地化 key
  var localizedTitleKey: String {
    switch self {
    case .both:
      return "delete_shortcut_option_both"
    case .backspace:
      return "delete_shortcut_option_backspace"
    case .forwardDelete:
      return "delete_shortcut_option_forward"
    case .none:
      return "delete_shortcut_option_none"
    }
  }
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
      return L10n.string("modifier_none")
    case .command:
      return L10n.string("modifier_command")
    case .option:
      return L10n.string("modifier_option")
    case .control:
      return L10n.string("modifier_control")
    case .shift:
      return L10n.string("modifier_shift")
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
      return L10n.string("language_system")
    case .chinese:
      return L10n.string("language_chinese")
    case .english:
      return L10n.string("language_english")
    }
  }

  /// 语言的 Locale 标识符（资源定位）
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

  /// 用于 SwiftUI 环境的 Locale 对象
  var locale: Locale {
    switch self {
    case .system:
      return .autoupdatingCurrent
    case .chinese:
      return Locale(identifier: "zh-Hans")
    case .english:
      return Locale(identifier: "en")
    }
  }

  /// 返回用户可选择的语言选项
  static func availableKeys() -> [AppLanguage] {
    return [.system, .chinese, .english]
  }
}

extension AppSettings {
  /// 根据业务选项应用固定的导航快捷键组合。
  func applyNavigationShortcuts(option: NavigationShortcutOption) -> Bool {
    guard option != .custom else { return true }

    let assignments: [(ShortcutAction, KeyboardShortcuts.Shortcut?)] = {
      switch option {
      case .leftRight:
        return [
          (.navigatePrevious, KeyboardShortcuts.Shortcut(.leftArrow)),
          (.navigateNext, KeyboardShortcuts.Shortcut(.rightArrow)),
        ]
      case .upDown:
        return [
          (.navigatePrevious, KeyboardShortcuts.Shortcut(.upArrow)),
          (.navigateNext, KeyboardShortcuts.Shortcut(.downArrow)),
        ]
      case .pageUpDown:
        return [
          (.navigatePrevious, KeyboardShortcuts.Shortcut(.pageUp)),
          (.navigateNext, KeyboardShortcuts.Shortcut(.pageDown)),
        ]
      case .custom:
        return []
      }
    }()

    return applyShortcutAssignments(assignments)
  }

  /// 根据用户偏好应用删除快捷键组合。
  private func applyDeleteShortcutPreference(_ preference: DeleteShortcutPreference) -> Bool {
    let assignments: [(ShortcutAction, KeyboardShortcuts.Shortcut?)] = {
      switch preference {
      case .both:
        return [
          (.deletePrimary, KeyboardShortcuts.Shortcut(.delete)),
          (.deleteSecondary, KeyboardShortcuts.Shortcut(.deleteForward)),
        ]
      case .backspace:
        return [
          (.deletePrimary, KeyboardShortcuts.Shortcut(.delete)),
          (.deleteSecondary, nil),
        ]
      case .forwardDelete:
        return [
          (.deletePrimary, KeyboardShortcuts.Shortcut(.deleteForward)),
          (.deleteSecondary, nil),
        ]
      case .none:
        return [
          (.deletePrimary, nil),
          (.deleteSecondary, nil),
        ]
      }
    }()

    return applyShortcutAssignments(assignments)
  }

  /// 提供快捷键的展示文本，供菜单或提示使用。
  func formattedShortcutDescription(for action: ShortcutAction) -> String? {
    guard let shortcut = shortcut(for: action) else { return nil }
    if Thread.isMainThread {
      return MainActor.assumeIsolated {
        shortcut.description
      }
    } else {
      return DispatchQueue.main.sync {
        MainActor.assumeIsolated {
          shortcut.description
        }
      }
    }
  }
}

private extension KeyboardShortcuts.Shortcut {
  /// 判断快捷键是否匹配指定按键与修饰键组合。
  func matches(key: KeyboardShortcuts.Key, modifiers: NSEvent.ModifierFlags) -> Bool {
    self.key == key && self.modifiers == modifiers
  }
}

private extension AppSettings {
  /// 禁用指定动作在 KeyboardShortcuts 中的全局注册，避免后台劫持按键。
  func deactivateShortcut(for action: ShortcutAction) {
    guard let definition = shortcutCatalog.definition(for: action) else { return }
    KeyboardShortcuts.disable([definition.name])
  }

  /// 禁用所有自定义快捷键的全局注册。
  func deactivateAllShortcuts() {
    let names = shortcutCatalog.definitions.values.map(\.name)
    KeyboardShortcuts.disable(names)
  }

  /// 查找与目标快捷键冲突的内部动作。
  func findAppLevelConflict(
    for targetShortcut: KeyboardShortcuts.Shortcut,
    excluding action: ShortcutAction,
    additionalIgnored: Set<ShortcutAction> = []
  ) -> ShortcutAction? {
    let ignored = additionalIgnored.union([action])
    for candidate in ShortcutAction.allCases where !ignored.contains(candidate) {
      guard let otherShortcut = shortcut(for: candidate) else { continue }
      if otherShortcut == targetShortcut {
        return candidate
      }
    }
    return nil
  }

  /// 恢复录制器到原有值（或清空）。
  func restoreShortcut(
    _ shortcut: KeyboardShortcuts.Shortcut?,
    for name: KeyboardShortcuts.Name
  ) {
    KeyboardShortcuts.setShortcut(shortcut, for: name)
  }

  /// 弹窗提示应用内快捷键冲突。
  func presentConflictAlert(conflictingAction: ShortcutAction, shortcut: KeyboardShortcuts.Shortcut)
  {
    let title = L10n.string("shortcut_conflict_title")
    let message = String(
      format: L10n.string("shortcut_conflict_message"),
      shortcutDisplayText(shortcut),
      conflictingAction.localizedDisplayName
    )
    let window = NSApp.keyWindow ?? NSApp.mainWindow
    presentAlert(title: title, message: message, window: window)
  }

  /// 统一创建并展示警告对话框。
  func presentAlert(title: String, message: String, window: NSWindow?) {
    let presentBlock = {
      let alert = NSAlert()
      alert.alertStyle = .warning
      alert.messageText = title
      alert.informativeText = message
      alert.addButton(withTitle: L10n.string("ok_button"))
      if let window {
        alert.beginSheetModal(for: window, completionHandler: nil)
      } else {
        alert.runModal()
      }
    }

    if Thread.isMainThread {
      presentBlock()
    } else {
      DispatchQueue.main.async(execute: presentBlock)
    }
  }

  /// 线程安全地获取快捷键描述文本。
  func shortcutDisplayText(_ shortcut: KeyboardShortcuts.Shortcut) -> String {
    if Thread.isMainThread {
      return MainActor.assumeIsolated { shortcut.description }
    } else {
      return DispatchQueue.main.sync {
        MainActor.assumeIsolated { shortcut.description }
      }
    }
  }

  /// 迁移旧版本中使用 Control 组合的镜像快捷键，避免冲突系统默认行为。
  static func migrateLegacyShortcuts() {
    let legacyHorizontal = KeyboardShortcuts.Shortcut(.h, modifiers: [.control])
    let legacyVertical = KeyboardShortcuts.Shortcut(.v, modifiers: [.control])
    let newHorizontal = KeyboardShortcuts.Shortcut(.h, modifiers: [.command, .shift])
    let newVertical = KeyboardShortcuts.Shortcut(.v, modifiers: [.command, .shift])

    if KeyboardShortcuts.getShortcut(for: .mirrorHorizontal) == legacyHorizontal {
      KeyboardShortcuts.setShortcut(newHorizontal, for: .mirrorHorizontal)
      KeyboardShortcuts.disable([.mirrorHorizontal])
    }
    if KeyboardShortcuts.getShortcut(for: .mirrorVertical) == legacyVertical {
      KeyboardShortcuts.setShortcut(newVertical, for: .mirrorVertical)
      KeyboardShortcuts.disable([.mirrorVertical])
    }
  }
  /// 批量检测冲突并写入快捷键，若成功返回 true，否则提示并返回 false。
  func applyShortcutAssignments(
    _ assignments: [(ShortcutAction, KeyboardShortcuts.Shortcut?)],
    conflictMessageOverride: ((KeyboardShortcuts.Shortcut, ShortcutAction) -> Void)? = nil
  ) -> Bool {
    let actionsToUpdate = Set(assignments.map(\.0))
    for (action, maybeShortcut) in assignments {
      guard let combo = maybeShortcut else { continue }
      if let conflict = findAppLevelConflict(
        for: combo,
        excluding: action,
        additionalIgnored: actionsToUpdate.subtracting([action])
      ) {
        if let customHandler = conflictMessageOverride {
          customHandler(combo, conflict)
        } else {
          presentConflictAlert(conflictingAction: conflict, shortcut: combo)
        }
        return false
      }
    }

    objectWillChange.send()
    for (action, maybeShortcut) in assignments {
      guard let definition = shortcutCatalog.definition(for: action) else { continue }
      KeyboardShortcuts.setShortcut(maybeShortcut, for: definition.name)
      deactivateShortcut(for: action)
    }
    return true
  }
}
