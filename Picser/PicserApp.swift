//
//  PicserApp.swift
//
//  Created by Eric Cai on 2025/8/18.
//

import SwiftUI

@main
struct PicserApp: App {
  // 创建全局设置管理器
  @StateObject private var appSettings = AppSettings()
  // 购买与试用状态管理器
  @StateObject private var purchaseManager: PurchaseManager
  // 功能权限守卫
  @StateObject private var featureGatekeeper: FeatureGatekeeper
  // 外部打开协调器
  @StateObject private var externalOpenCoordinator: ExternalOpenCoordinator
  // 本地化管理器（用于驱动 Locale 环境刷新）
  @ObservedObject private var localizationManager = LocalizationManager.shared
  // 应用委托
  @NSApplicationDelegateAdaptor private var appDelegate: PicserAppDelegate

  init() {
    let sharedSecret = PurchaseSecretsProvider.purchaseSharedSecret()
    let configuration = PurchaseConfiguration.loadDefault()
    let envReceiptToggle = ProcessInfo.processInfo.environment["PICSER_ENABLE_RECEIPT_VALIDATION"]
    // 在发布版本默认开启票据校验；仅当环境变量明确指定为 "0" 才关闭，调试版本仍需显式开启以便灵活测试
#if DEBUG
    let enableReceiptValidation = envReceiptToggle == "1"
#else
    let enableReceiptValidation = envReceiptToggle != "0"
#endif
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
    let openCoordinator = ExternalOpenCoordinator()
    _externalOpenCoordinator = StateObject(wrappedValue: openCoordinator)
    appDelegate.configure(externalOpenCoordinator: openCoordinator)
  }

  var body: some Scene {
    WindowGroup(id: "MainWindow") {
      ContentView()
        .environmentObject(appSettings)
        .environmentObject(purchaseManager)
        .environmentObject(featureGatekeeper)
        .environmentObject(externalOpenCoordinator)
        .environment(\.locale, localizationManager.currentLocale)
        .ignoresSafeArea(.all, edges: .top)
        // 处理外部打开的图片批次
        .onReceive(externalOpenCoordinator.latestBatchPublisher) { batch in
          if let window = NSApp.keyWindow ?? NSApp.mainWindow {
            window.makeKeyAndOrderFront(nil)
          }
        }
    }
    // 实现沉浸式看图：隐藏系统默认的标题栏
    .windowStyle(.hiddenTitleBar)
    .windowResizability(.contentSize)
    .defaultSize(CGSize(width: 1000, height: 700))
    .commands {
      AppCommands(recent: RecentOpensManager.shared, appSettings: appSettings)
    }

    // 设置窗口 - SwiftUI 会自动创建菜单项
    Settings {
      SettingsView(appSettings: appSettings)
        .environmentObject(purchaseManager)
        .environmentObject(featureGatekeeper)
        .environment(\.locale, localizationManager.currentLocale)
    }
  }
}
