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
    TabView {
      // 快捷键设置页面
      KeyboardSettingsView(appSettings: appSettings)
        .tabItem {
          Label("快捷键", systemImage: "keyboard")
        }

      // 显示设置页面
      DisplaySettingsView(appSettings: appSettings)
        .tabItem {
          Label("显示", systemImage: "display")
        }

      // 行为设置页面
      BehaviorSettingsView(appSettings: appSettings)
        .tabItem {
          Label("行为", systemImage: "gearshape")
        }
    }
    .frame(width: 500, height: 400)
    .onAppear {
      validateSettings()
    }
    .onChange(of: appSettings.zoomSensitivity) { _ in validateSettings() }
    .onChange(of: appSettings.minZoomScale) { _ in validateSettings() }
    .onChange(of: appSettings.maxZoomScale) { _ in validateSettings() }
    .onChange(of: appSettings.defaultZoomScale) { _ in validateSettings() }
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
      Text("快捷键设置")
        .font(.title2)
        .fontWeight(.semibold)

      Divider()

      // 缩放快捷键设置
      VStack(alignment: .leading, spacing: 8) {
        Text("缩放快捷键")
          .fontWeight(.medium)
        Text("配合鼠标滚轮缩放图片")
          .font(.caption)
          .foregroundColor(.secondary)

        KeyRecorderView(selectedKey: $appSettings.zoomModifierKey)
      }

      Divider()

      // 拖拽快捷键设置
      VStack(alignment: .leading, spacing: 8) {
        Text("拖拽快捷键")
          .fontWeight(.medium)
        Text("配合鼠标滚轮拖拽图片")
          .font(.caption)
          .foregroundColor(.secondary)

        KeyRecorderView(selectedKey: $appSettings.panModifierKey)
      }

      Spacer()

      // 重置按钮
      HStack {
        Spacer()
        Button("重置为默认值") {
          withAnimation {
            appSettings.zoomModifierKey = .control
            appSettings.panModifierKey = .none
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
      Text("显示设置")
        .font(.title2)
        .fontWeight(.semibold)

      Divider()

      // 缩放设置组
      VStack(alignment: .leading, spacing: 16) {
        Text("缩放设置")
          .fontWeight(.medium)

        // 默认缩放比例
        HStack {
          Text("默认缩放比例:")
            .frame(width: 120, alignment: .leading)
          Slider(
            value: $appSettings.defaultZoomScale,
            in: 0.1...3.0,
            step: 0.1
          )
          Text(String(format: "%.1f", appSettings.defaultZoomScale))
            .frame(width: 40, alignment: .trailing)
            .monospaced()
        }

        // 缩放灵敏度
        HStack {
          Text("缩放灵敏度:")
            .frame(width: 120, alignment: .leading)
          Slider(
            value: $appSettings.zoomSensitivity,
            in: 0.01...0.5,
            step: 0.01
          )
          Text(String(format: "%.2f", appSettings.zoomSensitivity))
            .frame(width: 40, alignment: .trailing)
            .monospaced()
        }

        // 最小缩放比例
        HStack {
          Text("最小缩放比例:")
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
          Text("最大缩放比例:")
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
        Button("重置为默认值") {
          withAnimation {
            appSettings.defaultZoomScale = 1.0
            appSettings.zoomSensitivity = 0.1
            appSettings.minZoomScale = 0.5
            appSettings.maxZoomScale = 10.0
          }
        }
        .buttonStyle(.bordered)
      }
    }
    .padding()
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }
}

// 行为设置页面
struct BehaviorSettingsView: View {
  @ObservedObject var appSettings: AppSettings

  var body: some View {
    VStack(alignment: .leading, spacing: 20) {
      Text("行为设置")
        .font(.title2)
        .fontWeight(.semibold)

      Divider()

      // 图片切换行为
      VStack(alignment: .leading, spacing: 16) {
        Text("图片切换时")
          .fontWeight(.medium)

        Toggle("重置缩放比例", isOn: $appSettings.resetZoomOnImageChange)
          .toggleStyle(CheckboxToggleStyle())

        Toggle("重置拖拽位置", isOn: $appSettings.resetPanOnImageChange)
          .toggleStyle(CheckboxToggleStyle())
      }

      Spacer()

      // 重置按钮
      HStack {
        Spacer()
        Button("重置为默认值") {
          withAnimation {
            appSettings.resetZoomOnImageChange = true
            appSettings.resetPanOnImageChange = true
          }
        }
        .buttonStyle(.bordered)
      }
    }
    .padding()
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }
}

// 自定义复选框样式
struct CheckboxToggleStyle: ToggleStyle {
  func makeBody(configuration: Configuration) -> some View {
    HStack {
      Image(systemName: configuration.isOn ? "checkmark.square" : "square")
        .foregroundColor(configuration.isOn ? .accentColor : .secondary)
        .onTapGesture {
          configuration.isOn.toggle()
        }

      configuration.label
    }
  }
}

// 预览
#Preview {
  SettingsView(appSettings: AppSettings())
}
