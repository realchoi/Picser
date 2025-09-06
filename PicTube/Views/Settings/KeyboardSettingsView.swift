//
//  KeyboardSettingsView.swift
//  PicTube
//
//  Created by Eric Cai on 2025/8/23.
//

import AppKit
import SwiftUI

// 快捷键设置页面
struct KeyboardSettingsView: View {
  @ObservedObject var appSettings: AppSettings

  var body: some View {
    VStack(alignment: .leading, spacing: 20) {
      Text(NSLocalizedString("keyboard_settings_title", comment: "Keyboard settings title"))
        .font(.title2)
        .fontWeight(.semibold)

      Divider()

      // 缩放快捷键设置
      VStack(alignment: .leading, spacing: 8) {
        Text(NSLocalizedString("zoom_shortcut_label", comment: "Zoom shortcut label"))
          .fontWeight(.medium)
        Text(NSLocalizedString("zoom_shortcut_description", comment: "Zoom shortcut description"))
          .font(.caption)
          .foregroundColor(.secondary)

        KeyPickerView(selectedKey: $appSettings.zoomModifierKey)
      }

      Divider()

      // 拖拽快捷键设置
      VStack(alignment: .leading, spacing: 8) {
        Text(NSLocalizedString("pan_shortcut_label", comment: "Pan shortcut label"))
          .fontWeight(.medium)
        Text(NSLocalizedString("pan_shortcut_description", comment: "Pan shortcut description"))
          .font(.caption)
          .foregroundColor(.secondary)

        KeyPickerView(selectedKey: $appSettings.panModifierKey)
      }

      Divider()

      // 图片切换按键设置
      VStack(alignment: .leading, spacing: 8) {
        Text(NSLocalizedString("image_navigation_label", comment: "Image navigation label"))
          .fontWeight(.medium)
        Text(
          NSLocalizedString("image_navigation_description", comment: "Image navigation description")
        )
        .font(.caption)
        .foregroundColor(.secondary)

        KeyPickerView(selectedKey: $appSettings.imageNavigationKey)
      }

      Spacer()

      // 重置按钮
      HStack {
        Spacer()
        Button(NSLocalizedString("reset_defaults_button", comment: "Reset defaults button")) {
          withAnimation {
            appSettings.resetToDefaults()
          }
        }
        .buttonStyle(.bordered)
      }
      // 移除额外的底部间距，与显示页面保持一致
    }
    .padding()
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
