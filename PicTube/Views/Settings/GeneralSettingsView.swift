//
//  GeneralSettingsView.swift
//  PicTube
//
//  Created by Eric Cai on 2025/09/06.
//

import SwiftUI

struct GeneralSettingsView: View {
  @ObservedObject var appSettings: AppSettings
  @ObservedObject private var localizationManager = LocalizationManager.shared
  @State private var showLanguageChangeNote = false

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 20) {
        Text("general_settings_title".localized)
          .font(.title2)
          .fontWeight(.semibold)

        Divider()

        // 界面设置组
        VStack(alignment: .leading, spacing: 16) {
          Text("interface_group".localized)
            .fontWeight(.medium)

          // 语言选择
          VStack(alignment: .leading, spacing: 8) {
            Text("app_language_label".localized)
              .fontWeight(.medium)
            Text("app_language_description".localized)
              .font(.caption)
              .foregroundColor(.secondary)

            HStack {
              Picker("", selection: $appSettings.appLanguage) {
                ForEach(AppLanguage.availableKeys(), id: \.self) { language in
                  Text(language.displayName).tag(language)
                }
              }
              .pickerStyle(.menu)
              .frame(minWidth: 120)
              .onChange(of: appSettings.appLanguage) {
                showLanguageChangeNote = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                  showLanguageChangeNote = false
                }
              }

              Spacer()
            }

            // 语言变更提示
            if showLanguageChangeNote {
              HStack {
                Image(systemName: "info.circle.fill")
                  .foregroundColor(.blue)
                  .font(.caption)

                Text("language_restart_note".localized)
                  .font(.caption)
                  .foregroundColor(.secondary)
              }
              .transition(.opacity.combined(with: .move(edge: .top)))
            }
          }
        }

        Spacer(minLength: 20)

        // 重置按钮
        HStack {
          Spacer()
          Button("reset_defaults_button".localized) {
            withAnimation {
              appSettings.resetToDefaults(settingsTab: .general)
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
  GeneralSettingsView(appSettings: AppSettings())
}
