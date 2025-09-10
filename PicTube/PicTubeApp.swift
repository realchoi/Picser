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
        // 绑定语言刷新触发器，切换语言时刷新整个视图树
        .id(LocalizationManager.shared.refreshTrigger)
        // 让试图内容延伸至标题栏区域，实现完全无边框效果
        .ignoresSafeArea(.all, edges: .top)
    }
    // 实现沉浸式看图：隐藏系统默认的标题栏
    .windowStyle(.hiddenTitleBar)
    .windowResizability(.contentSize)
    .commands {
      AppCommands(recent: RecentOpensManager.shared)
    }

    // 设置窗口 - SwiftUI 会自动创建菜单项
    Settings {
      SettingsView(appSettings: appSettings)
        // 绑定语言刷新触发器，切换语言时刷新设置窗口
        .id(LocalizationManager.shared.refreshTrigger)
    }
  }

}
