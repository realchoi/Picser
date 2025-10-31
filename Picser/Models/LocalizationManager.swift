//
//  LocalizationManager.swift
//
//  Created by Eric Cai on 2025/09/06.
//

import CoreFoundation
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

    // 同步 AppleLanguages，确保依赖 NSLocalizableString 的第三方库使用相同语言
    synchronizeAppleLanguages(with: localeIdentifier)
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

  /// 将当前应用语言同步到 `AppleLanguages`，便于第三方库读取一致语言。
  func synchronizeAppleLanguages(with identifier: String?) {
    var languages = Locale.preferredLanguages

    if let identifier {
      languages.removeAll(where: { $0.caseInsensitiveCompare(identifier) == .orderedSame })
      languages.insert(identifier, at: 0)
    }

    if languages.isEmpty {
      languages = [Locale.current.identifier]
    }

    func apply(to defaults: UserDefaults?) {
      guard let defaults else { return }
      let existingLanguages = defaults.array(forKey: "AppleLanguages") as? [String]
      if existingLanguages != languages {
        defaults.set(languages, forKey: "AppleLanguages")
      }
      if let identifier {
        if defaults.string(forKey: "AppleLocale") != identifier {
          defaults.set(identifier, forKey: "AppleLocale")
        }
      } else if defaults.object(forKey: "AppleLocale") != nil {
        defaults.removeObject(forKey: "AppleLocale")
      }
      defaults.synchronize()
    }

    apply(to: .standard)

    CFNotificationCenterPostNotification(CFNotificationCenterGetDistributedCenter(),
      CFNotificationName("AppleLanguagePreferencesChanged" as CFString),
      nil,
      nil,
      true)
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
