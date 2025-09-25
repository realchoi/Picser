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
  // 功能权限守卫
  @StateObject private var featureGatekeeper: FeatureGatekeeper

  init() {
    let sharedSecret = PurchaseSecretsProvider.purchaseSharedSecret()
    let configuration = PurchaseConfiguration.loadDefault()
    let enableReceiptValidation = ProcessInfo.processInfo.environment["PIXOR_ENABLE_RECEIPT_VALIDATION"] == "1"
    let manager = PurchaseManager(
      configuration: configuration,
      enableReceiptValidation: enableReceiptValidation,
      sharedSecret: sharedSecret
    )
    _purchaseManager = StateObject(wrappedValue: manager)
    // 配置功能权限守卫，允许未购买用户访问部分功能
    let policy = FeatureAccessPolicy(freeFeatures: [.exif])
    _featureGatekeeper = StateObject(
      wrappedValue: FeatureGatekeeper(
        purchaseManager: manager,
        policy: policy
      )
    )
  }

  var body: some Scene {
    WindowGroup {
      ContentView()
        .environmentObject(appSettings)
        .environmentObject(purchaseManager)
        .environmentObject(featureGatekeeper)
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
        .environmentObject(featureGatekeeper)
    }
  }

}
