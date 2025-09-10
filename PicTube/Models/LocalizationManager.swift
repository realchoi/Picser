//
//  LocalizationManager.swift
//  PicTube
//
//  Created by Eric Cai on 2025/09/06.
//

import Foundation
import SwiftUI

/// 动态本地化管理器，支持应用内实时语言切换
class LocalizationManager: ObservableObject {
  static let shared = LocalizationManager()

  @Published var currentLanguage: String = "system"
  @Published var refreshTrigger: UUID = UUID()  // 用于触发UI刷新
  private var currentBundle: Bundle = Bundle.main

  private init() {
    // 从UserDefaults加载保存的语言设置
    loadSavedLanguage()
    updateBundle()
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
    updateBundle()
    // 触发UI刷新
    refreshTrigger = UUID()
  }

  /// 根据当前语言设置更新Bundle
  private func updateBundle() {
    // 应用内可用的本地化（排除 Base）
    let available = Bundle.main.localizations.filter { $0 != "Base" }

    // 解析目标语言标识
    let localeIdentifier: String = {
      switch currentLanguage {
      case "chinese": return "zh-Hans"
      case "english": return "en"
      case "system":
        // 跟随系统，但只在应用内已支持的语言中选择
        let prefs = Locale.preferredLanguages
        if let match = Bundle.preferredLocalizations(from: available, forPreferences: prefs).first {
          return match
        }
        // 回退优先 en，其次任一可用语言
        if available.contains("en") { return "en" }
        return available.first ?? "en"
      default:
        return "en"
      }
    }()

    // 尝试加载指定语言的Bundle
    if let path = Bundle.main.path(forResource: localeIdentifier, ofType: "lproj"),
       let bundle = Bundle(path: path) {
      currentBundle = bundle
    } else {
      // 如果找不到指定语言包，使用默认Bundle
      currentBundle = Bundle.main
    }
  }

  /// 获取本地化字符串
  func localizedString(_ key: String, comment: String = "") -> String {
    return NSLocalizedString(key, bundle: currentBundle, comment: comment)
  }
}

/// String扩展，提供便捷的本地化方法
extension String {
  /// 获取动态本地化字符串
  var localized: String {
    // 通过访问refreshTrigger确保UI能监听到变化
    _ = LocalizationManager.shared.refreshTrigger
    return LocalizationManager.shared.localizedString(self)
  }

  /// 获取动态本地化字符串（带注释）
  func localized(comment: String) -> String {
    // 通过访问refreshTrigger确保UI能监听到变化
    _ = LocalizationManager.shared.refreshTrigger
    return LocalizationManager.shared.localizedString(self, comment: comment)
  }
}
