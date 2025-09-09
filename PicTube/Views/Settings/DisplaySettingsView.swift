//
//  DisplaySettingsView.swift
//  PicTube
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
        Text("display_settings_title".localized)
          .font(.title2)
          .fontWeight(.semibold)

        Divider()

        // 缩放设置组
        VStack(alignment: .leading, spacing: 16) {
          Text("zoom_settings_group".localized)
            .fontWeight(.medium)

          // 缩放灵敏度
          HStack {
            Text("zoom_sensitivity".localized)
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
            Text("min_zoom_scale".localized)
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
            Text("max_zoom_scale".localized)
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

        // 重置按钮
        HStack {
          Spacer()
          Button("reset_defaults_button".localized) {
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
