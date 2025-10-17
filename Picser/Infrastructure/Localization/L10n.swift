//
//  L10n.swift
//
//  Created by Eric Cai on 2025/10/14.
//

import SwiftUI

/// 统一管理本地化资源的入口，提供字符串与 LocalizedStringKey 的便捷获取方式。
enum L10n {
  /// 返回当前语言环境下的字符串，适用于 AppKit / NSAlert 等非 SwiftUI 场景。
  static func string(_ key: String, table: String? = nil, comment: String = "") -> String {
    LocalizationManager.shared.localizedString(key, table: table, comment: comment)
  }

  /// 返回 `LocalizedStringKey`，便于在 `Commands` 等需要键值的场景复用。
  static func key(_ key: String, table: String? = nil, comment: String = "") -> LocalizedStringKey {
    LocalizedStringKey(stringLiteral: string(key, table: table, comment: comment))
  }
}

extension Text {
  init(l10n key: String, table: String? = nil, comment: String = "") {
    self.init(L10n.string(key, table: table, comment: comment))
  }
}
