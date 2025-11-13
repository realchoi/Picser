//
//  TagOperationFeedback.swift
//
//  Created by Eric Cai on 2025/11/10.
//

import Foundation

/// 标签操作反馈事件
///
/// 用于在 UI 中展示操作结果提示（成功/失败）。
/// 携带本地化信息与时间戳，支持延迟本地化（运行时获取当前语言）。
///
/// 设计目标：
/// 1. 支持本地化消息，适应用户语言切换
/// 2. 区分成功和失败两种反馈类型
/// 3. 携带时间戳，便于记录和展示
///
/// 使用场景：
/// - 标签创建/更新/删除成功或失败
/// - 批量操作结果反馈
/// - 数据验证错误提示
struct TagOperationFeedback: Identifiable {
  /// 反馈类型
  enum Kind {
    /// 操作成功
    case success
    /// 操作失败
    case failure
  }

  /// 消息存储方式
  ///
  /// 支持两种消息类型：
  /// - literal：直接存储字符串，用于不需要本地化的消息
  /// - localized：存储本地化键和参数，运行时动态获取翻译
  ///
  /// 为什么需要延迟本地化：
  /// 1. 支持用户在运行时切换语言
  /// 2. 消息可能在创建时和显示时使用不同的语言
  /// 3. 避免在创建时就固化为某种语言的字符串
  enum Message {
    /// 直接字符串，不需要本地化
    case literal(String)
    /// 本地化键和格式化参数，运行时动态翻译
    case localized(key: String, arguments: [CVarArg] = [])
  }

  /// 唯一标识符，用于列表渲染和动画
  let id: UUID

  /// 反馈类型（成功/失败）
  let kind: Kind

  /// 事件发生时间
  let timestamp: Date

  /// 消息内容（延迟本地化）
  private let messageStorage: Message

  /// 初始化反馈事件
  ///
  /// - Parameters:
  ///   - id: 唯一标识符，默认自动生成
  ///   - kind: 反馈类型
  ///   - message: 消息内容
  ///   - timestamp: 事件时间戳，默认当前时间
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

  /// 获取本地化后的消息文本
  ///
  /// 根据 messageStorage 的类型，返回相应的本地化字符串。
  /// 对于 localized 类型，会在访问时动态获取当前语言的翻译。
  var message: String {
    switch messageStorage {
    case let .literal(text):
      return text
    case let .localized(key, arguments):
      return Self.localizedString(key: key, arguments: arguments)
    }
  }

  /// 是否为成功反馈
  var isSuccess: Bool { kind == .success }

  /// 是否为失败反馈
  var isFailure: Bool { kind == .failure }

  /// 获取本地化字符串
  ///
  /// 使用当前用户选择的语言进行格式化。
  /// 如果有格式化参数，使用 String.init(format:locale:arguments:) 进行格式化。
  ///
  /// - Parameters:
  ///   - key: 本地化键
  ///   - arguments: 格式化参数（例如：标签名称、数量等）
  /// - Returns: 格式化后的本地化字符串
  private static func localizedString(key: String, arguments: [CVarArg]) -> String {
    let format = L10n.string(key)
    guard !arguments.isEmpty else { return format }
    let locale = LocalizationManager.shared.currentLocale
    return String(format: format, locale: locale, arguments: arguments)
  }
}
