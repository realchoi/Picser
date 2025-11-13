//
//  TagOperationFeedback.swift
//
//  Created by Eric Cai on 2025/11/10.
//

import Foundation

/// 标签操作产生的提示事件，携带本地化信息与时间戳，便于在 UI 中动态展示
struct TagOperationFeedback: Identifiable {
  enum Kind {
    case success
    case failure
  }

  enum Message {
    case literal(String)
    case localized(key: String, arguments: [CVarArg] = [])
  }

  let id: UUID
  let kind: Kind
  let timestamp: Date
  private let messageStorage: Message

  init(
    id: UUID = UUID(),
    kind: Kind,
    message: Message,
    timestamp: Date = Date()
  ) {
    self.id = id
    self.kind = kind
    self.messageStorage = message
    self.timestamp = timestamp
  }

  var message: String {
    switch messageStorage {
    case let .literal(text):
      return text
    case let .localized(key, arguments):
      return Self.localizedString(key: key, arguments: arguments)
    }
  }

  var isSuccess: Bool { kind == .success }
  var isFailure: Bool { kind == .failure }

  private static func localizedString(key: String, arguments: [CVarArg]) -> String {
    let format = L10n.string(key)
    guard !arguments.isEmpty else { return format }
    let locale = LocalizationManager.shared.currentLocale
    return String(format: format, locale: locale, arguments: arguments)
  }
}
