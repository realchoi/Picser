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

    // 设置窗口 - SwiftUI 会自动创建菜单项
    Settings {
      SettingsView(appSettings: appSettings)
    }
  }

}
