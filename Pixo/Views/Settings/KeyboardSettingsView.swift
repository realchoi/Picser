//
//  KeyboardSettingsView.swift
//  Pixo
//
//  Created by Eric Cai on 2025/8/23.
//

import AppKit
import SwiftUI

// 快捷键设置页面
struct KeyboardSettingsView: View {
  @ObservedObject var appSettings: AppSettings

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 20) {
        Text("keyboard_settings_title".localized)
          .font(.title2)
          .fontWeight(.semibold)

        Divider()

        // 缩放快捷键设置
        VStack(alignment: .leading, spacing: 8) {
          Text("zoom_shortcut_label".localized)
            .fontWeight(.medium)
          Text("zoom_shortcut_description".localized)
            .font(.caption)
            .foregroundColor(.secondary)

          KeyPickerView(selectedKey: $appSettings.zoomModifierKey)
        }

        Divider()

        // 拖拽快捷键设置
        VStack(alignment: .leading, spacing: 8) {
          Text("pan_shortcut_label".localized)
            .fontWeight(.medium)
          Text("pan_shortcut_description".localized)
            .font(.caption)
            .foregroundColor(.secondary)

          KeyPickerView(selectedKey: $appSettings.panModifierKey)
        }

        Divider()

        // 图片切换按键设置
        VStack(alignment: .leading, spacing: 8) {
          Text("image_navigation_label".localized)
            .fontWeight(.medium)
          Text("image_navigation_description".localized)
            .font(.caption)
            .foregroundColor(.secondary)

        KeyPickerView(selectedKey: $appSettings.imageNavigationKey)
        }

        Divider()

        // 图像变换快捷键设置
        VStack(alignment: .leading, spacing: 12) {
          Text("transform_shortcuts_title".localized)
            .fontWeight(.medium)

          // 旋转左
          HStack(spacing: 10) {
            Text("rotate_ccw_shortcut_label".localized)
              .frame(width: 180, alignment: .leading)
            KeyPickerView(selectedKey: $appSettings.rotateCCWBaseKey)
            Text("+")
              .foregroundColor(.secondary)
            KeyPickerView(selectedKey: $appSettings.rotateCCWModifierKey)
          }

          // 旋转右
          HStack(spacing: 10) {
            Text("rotate_cw_shortcut_label".localized)
              .frame(width: 180, alignment: .leading)
            KeyPickerView(selectedKey: $appSettings.rotateCWBaseKey)
            Text("+")
              .foregroundColor(.secondary)
            KeyPickerView(selectedKey: $appSettings.rotateCWModifierKey)
          }

          // 水平镜像
          HStack(spacing: 10) {
            Text("mirror_horizontal_shortcut_label".localized)
              .frame(width: 180, alignment: .leading)
            KeyPickerView(selectedKey: $appSettings.mirrorHBaseKey)
            Text("+")
              .foregroundColor(.secondary)
            KeyPickerView(selectedKey: $appSettings.mirrorHModifierKey)
          }

          // 垂直镜像
          HStack(spacing: 10) {
            Text("mirror_vertical_shortcut_label".localized)
              .frame(width: 180, alignment: .leading)
            KeyPickerView(selectedKey: $appSettings.mirrorVBaseKey)
            Text("+")
              .foregroundColor(.secondary)
            KeyPickerView(selectedKey: $appSettings.mirrorVModifierKey)
          }

          // 重置图像变换
          HStack(spacing: 10) {
            Text("reset_transform_shortcut_label".localized)
              .frame(width: 180, alignment: .leading)
            KeyPickerView(selectedKey: $appSettings.resetTransformBaseKey)
            Text("+")
              .foregroundColor(.secondary)
            KeyPickerView(selectedKey: $appSettings.resetTransformModifierKey)
          }

          // 冲突提示
          if hasTransformShortcutConflict {
            HStack(alignment: .top, spacing: 8) {
              Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
              VStack(alignment: .leading, spacing: 4) {
                Text("transform_shortcut_conflict".localized)
                  .foregroundColor(.orange)
                  .font(.callout)
                // 逐条列出重复冲突
                ForEach(duplicateConflictItems(), id: \.self) { line in
                  Text("• \(line)")
                    .foregroundColor(.orange)
                    .font(.caption)
                }
              }
            }
            .padding(.top, 6)
          }

          if hasReservedShortcutUsage {
            HStack(alignment: .top, spacing: 8) {
              Image(systemName: "exclamationmark.octagon.fill")
                .foregroundColor(.red)
              VStack(alignment: .leading, spacing: 4) {
                Text("transform_shortcut_reserved".localized)
                  .foregroundColor(.red)
                  .font(.callout)
                // 逐条列出保留快捷键冲突
                ForEach(reservedConflictItems(), id: \.self) { line in
                  Text("• \(line)")
                    .foregroundColor(.red)
                    .font(.caption)
                }
              }
            }
          }
        }

        Spacer(minLength: 20)

        // 重置按钮
        HStack {
          Spacer()
          Button("reset_defaults_button".localized) {
            withAnimation {
              appSettings.resetToDefaults(settingsTab: .keyboard)
            }
          }
          .buttonStyle(.bordered)
        }
        // 移除额外的底部间距，与显示页面保持一致
      }
      .padding()
      .frame(maxWidth: .infinity, minHeight: 350, alignment: .topLeading)
    }
    .scrollIndicators(.visible)
  }
}

// MARK: - Helpers (conflict detection)
extension KeyboardSettingsView {
  private var hasTransformShortcutConflict: Bool {
    struct Combo: Hashable { let base: ShortcutBaseKey; let mod: ModifierKey }
    let combos: [Combo] = [
      Combo(base: appSettings.rotateCCWBaseKey, mod: appSettings.rotateCCWModifierKey),
      Combo(base: appSettings.rotateCWBaseKey, mod: appSettings.rotateCWModifierKey),
      Combo(base: appSettings.mirrorHBaseKey, mod: appSettings.mirrorHModifierKey),
      Combo(base: appSettings.mirrorVBaseKey, mod: appSettings.mirrorVModifierKey),
      Combo(base: appSettings.resetTransformBaseKey, mod: appSettings.resetTransformModifierKey),
    ]
    var set = Set<Combo>()
    for c in combos {
      if set.contains(c) { return true }
      set.insert(c)
    }
    return false
  }

  private var hasReservedShortcutUsage: Bool {
    // 常见 macOS 保留快捷键（Command + H/Q/W/V/C/X/A/M 等）
    let reservedLetters: Set<ShortcutBaseKey> = [.h, .q, .w, .v, .c, .x, .a, .m]
    let pairs: [(ShortcutBaseKey, ModifierKey)] = [
      (appSettings.rotateCCWBaseKey, appSettings.rotateCCWModifierKey),
      (appSettings.rotateCWBaseKey, appSettings.rotateCWModifierKey),
      (appSettings.mirrorHBaseKey, appSettings.mirrorHModifierKey),
      (appSettings.mirrorVBaseKey, appSettings.mirrorVModifierKey),
      (appSettings.resetTransformBaseKey, appSettings.resetTransformModifierKey),
    ]
    for (base, mod) in pairs {
      if mod == .command && reservedLetters.contains(base) { return true }
    }
    return false
  }

  // 列出重复冲突的详细条目
  private func duplicateConflictItems() -> [String] {
    struct Combo: Hashable { let base: ShortcutBaseKey; let mod: ModifierKey }
    struct Item { let label: String; let combo: Combo }
    let items: [Item] = [
      Item(label: "rotate_ccw_shortcut_label".localized, combo: .init(base: appSettings.rotateCCWBaseKey, mod: appSettings.rotateCCWModifierKey)),
      Item(label: "rotate_cw_shortcut_label".localized, combo: .init(base: appSettings.rotateCWBaseKey, mod: appSettings.rotateCWModifierKey)),
      Item(label: "mirror_horizontal_shortcut_label".localized, combo: .init(base: appSettings.mirrorHBaseKey, mod: appSettings.mirrorHModifierKey)),
      Item(label: "mirror_vertical_shortcut_label".localized, combo: .init(base: appSettings.mirrorVBaseKey, mod: appSettings.mirrorVModifierKey)),
      Item(label: "reset_transform_shortcut_label".localized, combo: .init(base: appSettings.resetTransformBaseKey, mod: appSettings.resetTransformModifierKey)),
    ]
    var map: [Combo: [Item]] = [:]
    for it in items { map[it.combo, default: []].append(it) }
    var lines: [String] = []
    for (combo, list) in map where list.count > 1 {
      // 将同一组合下的多个动作两两配对，合并为一条提示
      let names = list.map { $0.label }
      let joined = names.joined(separator: ", ")
      let comboStr = humanReadableCombo((base: combo.base, mod: combo.mod))
      let pattern = "transform_conflict_duplicate_item".localized // "%@ and %@ both set to %@" or generic
      if list.count == 2 {
        let a = names[0], b = names[1]
        lines.append(String(format: pattern, a, b, comboStr))
      } else {
        // 3 个及以上时，直接列出所有名称 + 组合
        lines.append("\(joined) — \(comboStr)")
      }
    }
    return lines
  }

  // 列出可能与系统保留快捷键冲突的条目
  private func reservedConflictItems() -> [String] {
    let reservedLetters: Set<ShortcutBaseKey> = [.h, .q, .w, .v, .c, .x, .a, .m]
    let pairs: [(label: String, base: ShortcutBaseKey, mod: ModifierKey)] = [
      ("rotate_ccw_shortcut_label".localized, appSettings.rotateCCWBaseKey, appSettings.rotateCCWModifierKey),
      ("rotate_cw_shortcut_label".localized, appSettings.rotateCWBaseKey, appSettings.rotateCWModifierKey),
      ("mirror_horizontal_shortcut_label".localized, appSettings.mirrorHBaseKey, appSettings.mirrorHModifierKey),
      ("mirror_vertical_shortcut_label".localized, appSettings.mirrorVBaseKey, appSettings.mirrorVModifierKey),
      ("reset_transform_shortcut_label".localized, appSettings.resetTransformBaseKey, appSettings.resetTransformModifierKey),
    ]
    var lines: [String] = []
    let pattern = "transform_conflict_reserved_item".localized // "%@ uses macOS-reserved shortcut %@"
    for p in pairs where p.mod == .command && reservedLetters.contains(p.base) {
      lines.append(String(format: pattern, p.label, humanReadableCombo((p.base, p.mod))))
    }
    return lines
  }

  // 组合的文字表示，例如："⌘ + ["、"⌥ + 0"、"V"（无修饰）
  private func humanReadableCombo(_ combo: (base: ShortcutBaseKey, mod: ModifierKey)) -> String {
    let base = humanReadableBase(combo.base)
    let mod = symbol(for: combo.mod)
    return mod.isEmpty ? base : "\(mod) + \(base)"
  }

  private func humanReadableBase(_ base: ShortcutBaseKey) -> String {
    return base.displayName
  }

  private func symbol(for mod: ModifierKey) -> String {
    switch mod {
    case .none: return ""
    case .command: return "⌘"
    case .option: return "⌥"
    case .control: return "⌃"
    case .shift: return "⇧"
    }
  }
}

// 通用键选择器视图
struct KeyPickerView<T: KeySelectable & Hashable>: View {
  @Binding var selectedKey: T

  var body: some View {
    HStack {
      // 键选择器
      Picker("", selection: $selectedKey) {
        ForEach(T.availableKeys()) { key in
          Text(key.displayName)
            .tag(key)
        }
      }
      .pickerStyle(.menu)
      .frame(minWidth: 120)
    }
  }
}

// 预览
#Preview {
  KeyboardSettingsView(appSettings: AppSettings())
}
