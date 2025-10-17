//
//  DisplaySettingsView.swift
//
//  Created by Eric Cai on 2025/8/23.
//

import AppKit
import SwiftUI

// 显示设置页面
struct DisplaySettingsView: View {
  @ObservedObject var appSettings: AppSettings

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 20) {
        Text(l10n: "display_settings_title")
          .font(.title2)
          .fontWeight(.semibold)

        Divider()

        // 缩放设置组
      VStack(alignment: .leading, spacing: 16) {
        Text(l10n: "zoom_settings_group")
          .fontWeight(.medium)

          // 缩放灵敏度
          HStack {
            Text(l10n: "zoom_sensitivity")
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
            Text(l10n: "min_zoom_scale")
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
            Text(l10n: "max_zoom_scale")
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

      Spacer(minLength: 20)

      // 小地图设置组
      VStack(alignment: .leading, spacing: 16) {
        Text(l10n: "minimap_group")
          .fontWeight(.medium)

        // 显示小地图开关
        Toggle(isOn: $appSettings.showMinimap) {
          Text(l10n: "show_minimap")
        }

        // 自动隐藏时间（0 = 关闭）
        HStack {
          Text(l10n: "minimap_auto_hide")
            .frame(width: 120, alignment: .leading)
          Slider(
            value: $appSettings.minimapAutoHideSeconds,
            in: 0...10,
            step: 1
          )
          Text(
            appSettings.minimapAutoHideSeconds <= 0
              ? L10n.string("minimap_auto_hide_off")
              : String(format: L10n.string("minimap_auto_hide_seconds_format"), appSettings.minimapAutoHideSeconds)
          )
          .frame(width: 60, alignment: .trailing)
          .monospaced()
        }
        .disabled(!appSettings.showMinimap)
        .opacity(appSettings.showMinimap ? 1 : 0.5)
      }

      Spacer(minLength: 20)

      // 图片扫描设置组
      VStack(alignment: .leading, spacing: 16) {
        Text(l10n: "image_scan_group")
          .fontWeight(.medium)

        Toggle(isOn: $appSettings.imageScanRecursively) {
          Text(l10n: "image_scan_recursive_toggle")
        }
      }

      // 重置按钮
      HStack {
        Spacer()
        Button(L10n.key("reset_defaults_button")) {
            withAnimation {
              appSettings.resetToDefaults(settingsTab: .display)
            }
          }
          .buttonStyle(.bordered)
        }
      }
      .padding()
      .frame(maxWidth: .infinity, minHeight: 350, alignment: .topLeading)
    }
    .scrollIndicators(.visible)
  }
}

// 预览
#Preview {
  DisplaySettingsView(appSettings: AppSettings())
}
