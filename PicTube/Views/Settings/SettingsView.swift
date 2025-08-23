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

        // 缓存管理页面
        CacheSettingsView()
          .tabItem {
            Label(
              NSLocalizedString("cache_tab", comment: "Cache tab title"),
              systemImage: "externaldrive"
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

// 预览
#Preview {
  SettingsView(appSettings: AppSettings())
}
