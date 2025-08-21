//
//  SettingsView.swift
//  PicTube
//
//  Created by Eric Cai on 2025/8/19.
//

import SwiftUI

struct SettingsView: View {
  @ObservedObject var appSettings: AppSettings
  @State private var validationErrors: [String] = []

  var body: some View {
    VStack(spacing: 0) {
      TabView {
        // 快捷键设置页面
        KeyboardSettingsView(appSettings: appSettings)
          .tabItem {
            Label(
              NSLocalizedString("keyboard_tab", comment: "Keyboard tab title"),
              systemImage: "keyboard")
          }

        // 显示设置页面
        DisplaySettingsView(appSettings: appSettings)
          .tabItem {
            Label(
              NSLocalizedString("display_tab", comment: "Display tab title"), systemImage: "display"
            )
          }
      }

      if !validationErrors.isEmpty {
        Divider()
        VStack(alignment: .leading, spacing: 6) {
          ForEach(validationErrors, id: \.self) { err in
            HStack(spacing: 8) {
              Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.yellow)
              Text(err)
                .font(.footnote)
                .foregroundColor(.secondary)
            }
          }
        }
        .padding(12)
      }
    }
    .frame(width: 500, height: 400)
    .onAppear { validateSettings() }
    .onChange(of: appSettings.zoomSensitivity) { validateSettings() }
    .onChange(of: appSettings.minZoomScale) { validateSettings() }
    .onChange(of: appSettings.maxZoomScale) { validateSettings() }
  }

  private func validateSettings() {
    validationErrors = appSettings.validateSettings()
  }
}

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

        KeyRecorderView(selectedKey: $appSettings.zoomModifierKey)
      }

      Divider()

      // 拖拽快捷键设置
      VStack(alignment: .leading, spacing: 8) {
        Text(NSLocalizedString("pan_shortcut_label", comment: "Pan shortcut label"))
          .fontWeight(.medium)
        Text(NSLocalizedString("pan_shortcut_description", comment: "Pan shortcut description"))
          .font(.caption)
          .foregroundColor(.secondary)

        KeyRecorderView(selectedKey: $appSettings.panModifierKey)
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
    }
    .padding()
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }
}

// 显示设置页面
struct DisplaySettingsView: View {
  @ObservedObject var appSettings: AppSettings

  var body: some View {
    VStack(alignment: .leading, spacing: 20) {
      Text(NSLocalizedString("display_settings_title", comment: "Display settings title"))
        .font(.title2)
        .fontWeight(.semibold)

      Divider()

      // 缩放设置组
      VStack(alignment: .leading, spacing: 16) {
        Text(NSLocalizedString("zoom_settings_group", comment: "Zoom settings group"))
          .fontWeight(.medium)

        // 缩放灵敏度
        HStack {
          Text(NSLocalizedString("zoom_sensitivity", comment: "Zoom sensitivity"))
            .frame(width: 120, alignment: .leading)
          Slider(
            value: $appSettings.zoomSensitivity,
            in: 0.01...0.1,
            step: 0.01
          )
          Text(String(format: "%.2f", appSettings.zoomSensitivity))
            .frame(width: 40, alignment: .trailing)
            .monospaced()
        }

        // 最小缩放比例
        HStack {
          Text(NSLocalizedString("min_zoom_scale", comment: "Minimum zoom scale"))
            .frame(width: 120, alignment: .leading)
          Slider(
            value: $appSettings.minZoomScale,
            in: 0.1...1.0,
            step: 0.1
          )
          Text(String(format: "%.1f", appSettings.minZoomScale))
            .frame(width: 40, alignment: .trailing)
            .monospaced()
        }

        // 最大缩放比例
        HStack {
          Text(NSLocalizedString("max_zoom_scale", comment: "Maximum zoom scale"))
            .frame(width: 120, alignment: .leading)
          Slider(
            value: $appSettings.maxZoomScale,
            in: 2.0...20.0,
            step: 0.5
          )
          Text(String(format: "%.1f", appSettings.maxZoomScale))
            .frame(width: 40, alignment: .trailing)
            .monospaced()
        }
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
    }
    .padding()
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }
}

// 预览
#Preview {
  SettingsView(appSettings: AppSettings())
}
