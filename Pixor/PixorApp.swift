//
//  PixorApp.swift
//  Pixor
//
//  Created by Eric Cai on 2025/8/18.
//

import SwiftUI

@main
struct PixorApp: App {
  // 创建全局设置管理器
  @StateObject private var appSettings = AppSettings()
  // 购买与试用状态管理器
  @StateObject private var purchaseManager: PurchaseManager

  init() {
    let sharedSecret = SecretsProvider.purchaseSharedSecret()
    let productIdentifier = SecretsProvider.purchaseProductIdentifier()
    let enableReceiptValidation = ProcessInfo.processInfo.environment["PIXOR_ENABLE_RECEIPT_VALIDATION"] == "1"
    _purchaseManager = StateObject(
      wrappedValue: PurchaseManager(
        productIdentifier: productIdentifier,
        enableReceiptValidation: enableReceiptValidation,
        sharedSecret: sharedSecret
      )
    )
  }

  var body: some Scene {
    WindowGroup {
      ContentView()
        .environmentObject(appSettings)
        .environmentObject(purchaseManager)
        // 让试图内容延伸至标题栏区域，实现完全无边框效果
        .ignoresSafeArea(.all, edges: .top)
    }
    // 实现沉浸式看图：隐藏系统默认的标题栏
    .windowStyle(.hiddenTitleBar)
    .windowResizability(.contentSize)
    .commands {
      AppCommands(recent: RecentOpensManager.shared, appSettings: appSettings)
    }

    // 设置窗口 - SwiftUI 会自动创建菜单项
    Settings {
      SettingsView(appSettings: appSettings)
        .environmentObject(purchaseManager)
    }
  }

}
