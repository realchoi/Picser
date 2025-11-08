//
//  KeyboardSettingsView.swift
//
//  Created by Eric Cai on 2025/8/23.
//

import SwiftUI
import KeyboardShortcuts

// 快捷键设置页面
struct KeyboardSettingsView: View {
  @ObservedObject var appSettings: AppSettings
  @ObservedObject private var localizationManager = LocalizationManager.shared
  /// 标签列固定宽度，保证主控件对齐且不触发复杂的自适应测量
  private let labelColumnWidth: CGFloat = 180
  /// KeyboardShortcuts 录制器在界面上的最小宽度，确保按钮内容不被裁剪
  private let recorderMinWidth: CGFloat = 220
  /// 统一的快捷键定义表，便于在 View 内获取 Name 等信息
  private let shortcutCatalog = KeyboardShortcutCatalog.shared
  /// 缓存各动作的当前快捷键，支持冲突时恢复
  @State private var cachedShortcuts: [ShortcutAction: KeyboardShortcuts.Shortcut?] = [:]
  var body: some View {
    VStack(alignment: .leading, spacing: 20) {
      headerSection
      Divider()
      zoomSection
      Divider()
      panSection
      Divider()
      transformSection
      Divider()
      navigationSection
      Divider()
      deleteSection
      Spacer().frame(height: 20)
      resetSection
    }
    .frame(maxWidth: .infinity, alignment: .topLeading)
    .settingsContentContainer()
    .onAppear {
      populateShortcutCache()
    }
    .onChange(of: appSettings.deleteShortcutOptions) { _, _ in
      populateShortcutCache(for: [.deleteForward, .deleteBackspace])
    }
    .onChange(of: appSettings.imageNavigationOptions) { _, _ in
      populateShortcutCache(for: [.navigatePrevious, .navigateNext])
    }
  }

  /// 页面标题
  private var headerSection: some View {
    Text(l10n: "keyboard_settings_title")
      .font(.title2)
      .fontWeight(.semibold)
  }

  /// 缩放手势修饰键配置
  private var zoomSection: some View {
    labelledPickerRow(
      labelKey: "zoom_shortcut_label",
      descriptionKey: "zoom_shortcut_description"
    ) {
      KeyPickerView(selectedKey: $appSettings.zoomModifierKey)
    }
  }

  /// 拖拽手势修饰键配置
  private var panSection: some View {
    labelledPickerRow(
      labelKey: "pan_shortcut_label",
      descriptionKey: "pan_shortcut_description"
    ) {
      KeyPickerView(selectedKey: $appSettings.panModifierKey)
    }
  }

  /// 图片导航快捷键配置
  private var navigationSection: some View {
    multiSelectRow(
      titleKey: "image_navigation_label",
      descriptionKey: "image_navigation_description",
      options: NavigationShortcutOption.allCases,
      selections: $appSettings.imageNavigationOptions,
      labelColumnWidth: labelColumnWidth,
      contentMinWidth: recorderMinWidth
    )
  }

  /// 图像变换相关快捷键配置
  private var transformSection: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text(l10n: "transform_shortcuts_title")
        .fontWeight(.medium)

      recorderRow(labelKey: "rotate_ccw_shortcut_label", action: .rotateCounterclockwise)
      recorderRow(labelKey: "rotate_cw_shortcut_label", action: .rotateClockwise)
      recorderRow(labelKey: "mirror_horizontal_shortcut_label", action: .mirrorHorizontal)
      recorderRow(labelKey: "mirror_vertical_shortcut_label", action: .mirrorVertical)
      recorderRow(labelKey: "reset_transform_shortcut_label", action: .resetTransform)
    }
  }

  /// 删除操作快捷键配置
  /// 删除快捷键区域
  /// 说明：Delete 键（⌦）映射到 ShortcutAction.deleteForward，Backspace 键（⌫）映射到 ShortcutAction.deleteBackspace
  private var deleteSection: some View {
    VStack(alignment: .leading, spacing: 12) {
      multiSelectRow(
        titleKey: "delete_shortcut_section_title",
        descriptionKey: "delete_shortcut_section_description",
        options: DeleteShortcutOption.allCases,
        selections: $appSettings.deleteShortcutOptions,
        labelColumnWidth: labelColumnWidth,
        contentMinWidth: recorderMinWidth
      )

      Toggle(isOn: $appSettings.deleteConfirmationEnabled) {
        Text(l10n: "delete_confirmation_toggle")
          .fontWeight(.medium)
      }
      .toggleStyle(.checkbox)

      Text(l10n: "delete_confirmation_description")
        .font(.caption)
        .foregroundColor(.secondary)
    }
  }

  /// 重置按钮区域
  private var resetSection: some View {
    HStack {
      Spacer()
      Button(L10n.key("reset_defaults_button")) {
        withAnimation {
          appSettings.resetToDefaults(settingsTab: .keyboard)
        }
        populateShortcutCache()
      }
      .buttonStyle(.bordered)
    }
  }

  /// 通用的录制控件行布局
  private func recorderRow(labelKey: String, action: ShortcutAction) -> some View
  {
    VStack(alignment: .leading, spacing: 4) {
      HStack(alignment: .firstTextBaseline, spacing: 12) {
        Text(l10n: labelKey)
          .frame(width: labelColumnWidth, alignment: .leading)

        let definition = shortcutDefinition(for: action)
        KeyboardShortcuts.Recorder(for: definition.name) { shortcut in
          let previousShortcut = cachedShortcuts[action] ?? appSettings.shortcut(for: action)
          let result = appSettings.handleRecorderChange(
            for: action,
            newShortcut: shortcut,
            previousShortcut: previousShortcut
          )
          switch result {
          case .accepted:
            populateShortcutCache(for: [action])
          case .conflict(let conflicting):
            populateShortcutCache(for: [action, conflicting])
          }
        }
        .id(localizationManager.refreshTrigger)
        .frame(minWidth: recorderMinWidth, alignment: .leading)

        Spacer(minLength: 0)
      }
    }
  }

  /// 安全读取定义，若缺失则直接终止（属于开发期错误）
  private func shortcutDefinition(for action: ShortcutAction) -> ShortcutDefinition {
    guard let definition = shortcutCatalog.definition(for: action) else {
      preconditionFailure("Missing keyboard shortcut definition for \(action)")
    }
    return definition
  }

  /// 更新缓存数据，默认同步所有动作或指定动作。
  private func populateShortcutCache(for actions: [ShortcutAction]? = nil) {
    let targets = actions ?? Array(ShortcutAction.allCases)
    for target in targets {
      cachedShortcuts[target] = appSettings.shortcut(for: target)
    }
  }

  /// 带有统一布局的下拉选择行
  private func labelledPickerRow<PickerContent: View>(
    labelKey: String,
    descriptionKey: String?,
    @ViewBuilder picker: () -> PickerContent
  ) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack(alignment: .firstTextBaseline, spacing: 12) {
        Text(l10n: labelKey)
          .fontWeight(.medium)
          .frame(width: labelColumnWidth, alignment: .leading)
        picker()
          .frame(minWidth: recorderMinWidth, alignment: .leading)
        Spacer(minLength: 0)
      }
      if let descriptionKey {
        Text(l10n: descriptionKey)
          .font(.caption)
          .foregroundColor(.secondary)
      }
    }
  }

}

// 通用键选择器视图
struct KeyPickerView<T: KeySelectable & Hashable>: View {
  @Binding var selectedKey: T

  var body: some View {
    HStack {
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

/// 多选行组件，包含标题、描述和多个复选框选项
private func multiSelectRow<Option: Hashable & CustomStringConvertible>(
  titleKey: String,
  descriptionKey: String,
  options: [Option],
  selections: Binding<Set<Option>>,
  labelColumnWidth: CGFloat,
  contentMinWidth: CGFloat
) -> some View {
  HStack(alignment: .top, spacing: 12) {
    VStack(alignment: .leading, spacing: 4) {
      Text(l10n: titleKey)
        .fontWeight(.medium)

      Text(l10n: descriptionKey)
        .font(.caption)
        .foregroundColor(.secondary)
    }
    .frame(width: labelColumnWidth, alignment: .leading)

    MultiSelectToggleList(
      options: options,
      selections: selections
    )
    .frame(minWidth: contentMinWidth, alignment: .leading)

    Spacer(minLength: 0)
  }
}

/// 多选 Toggle 列表组件，以 Toggle 形式展示选项
struct MultiSelectToggleList<Option: Hashable & CustomStringConvertible>: View {
  let options: [Option]
  @Binding var selections: Set<Option>

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      ForEach(options, id: \.self) { option in
        Toggle(option.description, isOn: Binding(
          get: { selections.contains(option) },
          set: { newValue in
            if newValue {
              selections.insert(option)
            } else {
              selections.remove(option)
            }
          }
        ))
        .toggleStyle(.checkbox)
        .frame(maxWidth: .infinity, alignment: .leading)
      }
    }
  }
}

// 预览
#Preview {
  KeyboardSettingsView(appSettings: AppSettings())
}