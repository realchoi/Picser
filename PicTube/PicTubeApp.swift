//
//  PicTubeApp.swift
//  PicTube
//
//  Created by Eric Cai on 2025/8/18.
//

import SwiftUI

@main
struct PicTubeApp: App {
  // 创建全局设置管理器
  @StateObject private var appSettings = AppSettings()

  var body: some Scene {
    WindowGroup {
      ContentView()
        .environmentObject(appSettings)
    }
    .commands {
      // 添加设置菜单项
      CommandGroup(after: .appInfo) {
        Button("偏好设置...") {
          openSettings()
        }
        .keyboardShortcut(",", modifiers: .command)
      }
    }

    // 设置窗口
    Settings {
      SettingsView(appSettings: appSettings)
    }
  }

  private func openSettings() {
    // 打开设置窗口
    if #available(macOS 13.0, *) {
      NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    } else {
      NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
    }
  }
}
