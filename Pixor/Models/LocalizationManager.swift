//
//  LocalizationManager.swift
//  Pixor
//
//  Created by Eric Cai on 2025/09/06.
//

import Foundation
import SwiftUI

/// 动态本地化管理器，支持应用内实时语言切换
class LocalizationManager: ObservableObject {
  static let shared = LocalizationManager()

  @Published var currentLanguage: String = "system"
  @Published var currentLocale: Locale = .autoupdatingCurrent
  @Published var refreshTrigger: UUID = UUID()  // 用于触发UI刷新
  private var currentBundle: Bundle = Bundle.main

  private init() {
    // 从UserDefaults加载保存的语言设置
    loadSavedLanguage()
    updateBundleAndLocale()
  }

  /// 从UserDefaults加载保存的语言设置
  private func loadSavedLanguage() {
    let savedLanguage = UserDefaults.standard.string(forKey: "appLanguage") ?? "system"
    currentLanguage = savedLanguage
  }

  /// 设置应用语言
  func setLanguage(_ language: String) {
    currentLanguage = language
    UserDefaults.standard.set(language, forKey: "appLanguage")
    updateBundleAndLocale()
    // 触发UI刷新
    refreshTrigger = UUID()
  }

  /// 根据当前语言设置更新 Locale 与 Bundle
  private func updateBundleAndLocale() {
    // 应用内可用的本地化（排除 Base）
    let available = availableLocalizations()

    // 解析目标语言标识和 Locale
    let (localeIdentifier, locale) = resolvedLocale(for: currentLanguage, available: available)

    // 同步 Locale 对象，供 SwiftUI 环境使用
    currentLocale = locale

    // 定位目标语言的资源 Bundle（默认为主 Bundle）
    if let identifier = localeIdentifier,
       let path = Bundle.main.path(forResource: identifier, ofType: "lproj"),
       let bundle = Bundle(path: path) {
      currentBundle = bundle
    } else {
      currentBundle = Bundle.main
    }
  }

  /// 根据当前语言标识解析 Locale 信息（兼容跟随系统的场景）
  private func resolvedLocale(for language: String, available: [String]) -> (identifier: String?, locale: Locale) {
    switch language {
    case "chinese":
      let identifier = "zh-Hans"
      return (identifier, Locale(identifier: identifier))
    case "english":
      let identifier = "en"
      return (identifier, Locale(identifier: identifier))
    case "system":
      return (nil, .autoupdatingCurrent)
    default:
      return (language, Locale(identifier: language))
    }
  }

  /// 列出可用本地化（忽略 Base）
  private func availableLocalizations() -> [String] {
    return Bundle.main.localizations.filter { $0 != "Base" }
  }

  /// 获取本地化字符串
  func localizedString(_ key: String, table: String? = nil, comment: String = "") -> String {
    return currentBundle.localizedString(forKey: key, value: nil, table: table)
  }
}

/// String扩展，提供便捷的本地化方法
extension String {
  /// 获取动态本地化字符串
  @available(*, deprecated, message: "请改用 L10n.string(_:) 或 Text(l10n:)")
  var localized: String {
    // 通过访问refreshTrigger确保UI能监听到变化
    _ = LocalizationManager.shared.refreshTrigger
    return LocalizationManager.shared.localizedString(self)
  }

  /// 获取动态本地化字符串（带注释）
  @available(*, deprecated, message: "请改用 L10n.string(_:comment:) 或 Text(l10n:)")
  func localized(comment: String) -> String {
    // 通过访问refreshTrigger确保UI能监听到变化
    _ = LocalizationManager.shared.refreshTrigger
    return LocalizationManager.shared.localizedString(self, comment: comment)
  }
}
