//
//  LocalizedDateFormatter.swift
//  Picser
//
//  Created by Eric Cai on 2025/11/11.
//

import Foundation

enum LocalizedDateFormatter {
  /// 统一的简短日期时间展示
  static func shortTimestamp(for date: Date) -> String {
    let style = Date.FormatStyle(date: .abbreviated, time: .shortened)
      .locale(LocalizationManager.shared.currentLocale)
    return date.formatted(style)
  }
}
