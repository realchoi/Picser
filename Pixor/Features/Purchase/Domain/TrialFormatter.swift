//
//  TrialFormatter.swift
//  Pixor
//
//  Created by Eric Cai on 2025/9/19.
//

import Foundation

/// 试用期时间格式化工具
enum TrialFormatter {
  static func remainingDescription(now: Date = Date(), endDate: Date) -> String {
    let remaining = max(0, endDate.timeIntervalSince(now))
    if remaining < 60 {
      return L10n.string("trial_banner_remaining_less_than_minute")
    }

    let components = Calendar.current.dateComponents([.day, .hour, .minute], from: now, to: endDate)
    let day = max(0, components.day ?? 0)
    let hour = max(0, components.hour ?? 0)
    let minute = max(0, components.minute ?? 0)
    let locale = LocalizationManager.shared.currentLocale

    if day > 0 {
      return String(
        format: L10n.string("trial_banner_remaining_day_hour"),
        locale: locale,
        day,
        hour
      )
    }

    if hour > 0 {
      return String(
        format: L10n.string("trial_banner_remaining_hour_minute"),
        locale: locale,
        hour,
        minute
      )
    }

    return String(
      format: L10n.string("trial_banner_remaining_minute"),
      locale: locale,
      minute
    )
  }
}
