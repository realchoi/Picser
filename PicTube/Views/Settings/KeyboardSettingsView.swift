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
