//
//  KeyboardShortcutDefinitions.swift
//
//  提供统一的快捷键动作注册表和默认值描述，后续迁移与配置界面都以此为单一数据源。
//

import AppKit
import SwiftUI
import KeyboardShortcuts

/// 列举应用当前支持自定义的快捷键动作，方便统一管理并便于未来扩展。
enum ShortcutAction: CaseIterable {
  case rotateCounterclockwise
  case rotateClockwise
  case mirrorHorizontal
  case mirrorVertical
  case resetTransform
  case navigatePrevious
  case navigateNext
  case deletePrimary
  case deleteSecondary
}

/// 表示一个快捷键组合（按键 + 修饰键），可用于默认值配置与数据迁移。
struct ShortcutKeyCombination {
  /// 物理按键。使用 KeyboardShortcuts.Key 覆盖字母、符号、方向键等特殊键。
  let key: KeyboardShortcuts.Key
  /// 对应的修饰键集合（Command、Option 等）。
  let modifiers: NSEvent.ModifierFlags

  init(key: KeyboardShortcuts.Key, modifiers: NSEvent.ModifierFlags = []) {
    self.key = key
    self.modifiers = modifiers
  }

  /// 转换为 KeyboardShortcuts.Shortcut，便于注册默认值或回写配置。
  var toShortcut: KeyboardShortcuts.Shortcut {
    KeyboardShortcuts.Shortcut(key, modifiers: modifiers)
  }
}

/// 快捷键定义：描述动作名称与缺省快捷键集合。
struct ShortcutDefinition {
  /// 业务动作枚举值。
  let action: ShortcutAction
  /// 第三方库中注册所需的名称对象。
  let name: KeyboardShortcuts.Name
  /// 默认提供的一组快捷键组合。部分动作（如删除）可以提供多组以覆盖不同物理键。
  let defaultCombinations: [ShortcutKeyCombination]
}

/// 快捷键注册表，集中维护所有动作的定义，供 UI、迁移与运行时监听共用。
struct KeyboardShortcutCatalog {
  /// 单例访问，保持数据来源一致。
  static let shared = KeyboardShortcutCatalog()

  /// 具体定义映射，key 为业务动作，value 为对应描述。
  let definitions: [ShortcutAction: ShortcutDefinition]

  private init() {
    let rotateCCW = ShortcutDefinition(
      action: .rotateCounterclockwise,
      name: .rotateCounterclockwise,
      defaultCombinations: [
        ShortcutKeyCombination(key: .leftBracket, modifiers: [.command])
      ]
    )
    let rotateCW = ShortcutDefinition(
      action: .rotateClockwise,
      name: .rotateClockwise,
      defaultCombinations: [
        ShortcutKeyCombination(key: .rightBracket, modifiers: [.command])
      ]
    )
    let mirrorH = ShortcutDefinition(
      action: .mirrorHorizontal,
      name: .mirrorHorizontal,
      defaultCombinations: [
        ShortcutKeyCombination(key: .h, modifiers: [.command, .shift])
      ]
    )
    let mirrorV = ShortcutDefinition(
      action: .mirrorVertical,
      name: .mirrorVertical,
      defaultCombinations: [
        ShortcutKeyCombination(key: .v, modifiers: [.command, .shift])
      ]
    )
    let resetTransform = ShortcutDefinition(
      action: .resetTransform,
      name: .resetTransform,
      defaultCombinations: [
        ShortcutKeyCombination(key: .zero, modifiers: [.option])
      ]
    )
    let navigatePrevious = ShortcutDefinition(
      action: .navigatePrevious,
      name: .navigatePrevious,
      defaultCombinations: [
        ShortcutKeyCombination(key: .leftArrow)
      ]
    )
    let navigateNext = ShortcutDefinition(
      action: .navigateNext,
      name: .navigateNext,
      defaultCombinations: [
        ShortcutKeyCombination(key: .rightArrow)
      ]
    )
    let deletePrimary = ShortcutDefinition(
      action: .deletePrimary,
      name: .deletePrimary,
      defaultCombinations: [
        ShortcutKeyCombination(key: .delete)
      ]
    )
    let deleteSecondary = ShortcutDefinition(
      action: .deleteSecondary,
      name: .deleteSecondary,
      defaultCombinations: [
        ShortcutKeyCombination(key: .deleteForward)
      ]
    )

    definitions = [
      rotateCCW.action: rotateCCW,
      rotateCW.action: rotateCW,
      mirrorH.action: mirrorH,
      mirrorV.action: mirrorV,
      resetTransform.action: resetTransform,
      navigatePrevious.action: navigatePrevious,
      navigateNext.action: navigateNext,
      deletePrimary.action: deletePrimary,
      deleteSecondary.action: deleteSecondary,
    ]
  }

  /// 根据动作获取对应定义。
  /// - Parameter action: 业务动作。
  /// - Returns: 若已注册则返回定义，否则为 nil（便于未来动态扩展时处理缺省情况）。
  func definition(for action: ShortcutAction) -> ShortcutDefinition? {
    definitions[action]
  }
}

// MARK: - 提供与第三方库绑定的 Name 静态定义
extension KeyboardShortcuts.Name {
  /// 逆时针旋转
  static let rotateCounterclockwise = Self(
    "rotateCounterclockwise",
    default: KeyboardShortcuts.Shortcut(.leftBracket, modifiers: [.command])
  )
  /// 顺时针旋转
  static let rotateClockwise = Self(
    "rotateClockwise",
    default: KeyboardShortcuts.Shortcut(.rightBracket, modifiers: [.command])
  )
  /// 水平镜像
  static let mirrorHorizontal = Self(
    "mirrorHorizontal",
    default: KeyboardShortcuts.Shortcut(.h, modifiers: [.command, .shift])
  )
  /// 垂直镜像
  static let mirrorVertical = Self(
    "mirrorVertical",
    default: KeyboardShortcuts.Shortcut(.v, modifiers: [.command, .shift])
  )
  /// 重置图像变换
  static let resetTransform = Self(
    "resetTransform",
    default: KeyboardShortcuts.Shortcut(.zero, modifiers: [.option])
  )
  /// 上一张图片
  static let navigatePrevious = Self(
    "navigatePrevious",
    default: KeyboardShortcuts.Shortcut(.leftArrow)
  )
  /// 下一张图片
  static let navigateNext = Self(
    "navigateNext",
    default: KeyboardShortcuts.Shortcut(.rightArrow)
  )
  /// 删除（主快捷键，默认 Delete）
  static let deletePrimary = Self(
    "deletePrimary",
    default: KeyboardShortcuts.Shortcut(.delete)
  )
  /// 删除（备用快捷键，默认 Forward Delete）
  static let deleteSecondary = Self(
    "deleteSecondary",
    default: KeyboardShortcuts.Shortcut(.deleteForward)
  )
}

extension ShortcutAction {
  /// 返回动作在设置界面中展示的本地化名称。
  var localizedDisplayName: String {
    switch self {
    case .rotateCounterclockwise:
      return L10n.string("rotate_ccw_shortcut_label")
    case .rotateClockwise:
      return L10n.string("rotate_cw_shortcut_label")
    case .mirrorHorizontal:
      return L10n.string("mirror_horizontal_shortcut_label")
    case .mirrorVertical:
      return L10n.string("mirror_vertical_shortcut_label")
    case .resetTransform:
      return L10n.string("reset_transform_shortcut_label")
    case .navigatePrevious:
      return L10n.string("navigate_previous_action_name")
    case .navigateNext:
      return L10n.string("navigate_next_action_name")
    case .deletePrimary:
      return L10n.string("delete_primary_shortcut_label")
    case .deleteSecondary:
      return L10n.string("delete_secondary_shortcut_label")
    }
  }
}
