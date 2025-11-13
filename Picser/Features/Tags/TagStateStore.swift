//
//  TagStateStore.swift
//  Picser
//
//  Created by Eric Cai on 2025/11/13.
//  标签 UI 状态管理
//

import Foundation
import Combine

/// 标签 UI 状态存储
///
/// 集中管理所有标签相关的 UI 状态，与业务逻辑分离。
/// TagService 负责更新这些状态，UI 层订阅这些状态变化。
///
/// 职责：
/// - 管理 @Published 状态属性
/// - 提供状态访问接口
/// - 不包含业务逻辑
@MainActor
final class TagStateStore: ObservableObject {

  // MARK: - Core Data States

  /// 全局标签列表，按使用频次排序
  @Published var allTags: [TagRecord] = []

  /// 按名称排序的全局标签列表（用于某些 UI 场景）
  @Published var allTagsSortedByName: [TagRecord] = []

  /// 当前作用域（选中图片集合）内的标签统计信息
  @Published var scopedTags: [ScopedTagSummary] = []

  /// 图片路径到标签列表的映射缓存
  @Published var assignments: [String: [TagRecord]] = [:]

  // MARK: - Filter States

  /// 当前激活的筛选条件
  @Published var activeFilter: TagFilter = .init()

  /// 用户自定义的智能筛选集合
  @Published var smartFilters: [TagSmartFilter] = []

  // MARK: - Operation States

  /// 最近一次巡检的结果
  @Published var lastInspection: TagInspectionSummary = .empty

  /// 最近一次错误消息
  @Published var lastError: String?

  /// 最新的操作反馈事件
  @Published var feedbackEvent: TagOperationFeedback?

  /// 操作反馈历史记录
  @Published var feedbackHistory: [TagOperationFeedback] = []

  // MARK: - Public Interface

  /// 清除错误状态
  func clearError() {
    lastError = nil
  }

  /// 清除反馈事件
  func clearFeedback() {
    feedbackEvent = nil
  }

  /// 添加反馈到历史记录
  ///
  /// - Parameter feedback: 反馈事件
  func appendFeedback(_ feedback: TagOperationFeedback) {
    feedbackHistory.append(feedback)
    // 保持历史记录在合理范围内
    if feedbackHistory.count > 50 {
      feedbackHistory.removeFirst(feedbackHistory.count - 50)
    }
  }
}
