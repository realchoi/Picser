//
//  TagModels.swift
//
//  Created by Eric Cai on 2025/11/08.
//

import Foundation

/// 标签基础信息，包含 UI 需要的统计数据
struct TagRecord: Identifiable, Hashable {
  let id: Int64
  var name: String
  var colorHex: String?
  var usageCount: Int
  var createdAt: Date
  var updatedAt: Date
}

/// 当前图片集合内的标签统计
struct ScopedTagSummary: Identifiable, Hashable {
  let id: Int64
  var name: String
  var colorHex: String?
  var usageCount: Int
}

/// 图片条目，用于在数据库中跟踪文件与标签的关系
struct TaggedImageRecord: Identifiable, Hashable {
  let id: Int64
  let path: String
  let fileName: String
  let directory: String
  var createdAt: Date
  var updatedAt: Date
  /// macOS 文件唯一标识（便于断电恢复）
  var fileIdentifier: String?
  /// 安全书签数据，用于重新访问沙盒外文件
  var bookmarkData: Data?
}

/// 标签筛选模式
enum TagFilterMode: String, Codable, CaseIterable {
  case any  // 满足任意一个标签
  case all  // 必须同时满足全部标签
  case exclude  // 排除包含指定标签的图片
}

/// 标签筛选条件
struct TagFilter: Equatable, Codable {
  /// 标签匹配模式：任意/全部/排除
  var mode: TagFilterMode
  /// 参与筛选的标签 ID 集合
  var tagIDs: Set<Int64>
  /// 文件名/目录名关键字
  var keyword: String
  /// 需要匹配的标签颜色集合（#RRGGBB）
  var colorHexes: Set<String>

  init(
    mode: TagFilterMode = .any,
    tagIDs: Set<Int64> = [],
    keyword: String = "",
    colorHexes: Set<String> = []
  ) {
    self.mode = mode
    self.tagIDs = tagIDs
    self.keyword = keyword
    self.colorHexes = colorHexes
  }

  /// 任意一个条件生效即可视为筛选开启
  var isActive: Bool {
    let hasKeyword = !keyword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    return !tagIDs.isEmpty || hasKeyword || !colorHexes.isEmpty
  }
}

/// 可命名的筛选器快照，便于快速切换常用组合
struct TagSmartFilter: Identifiable, Codable, Equatable {
  let id: UUID
  var name: String
  var filter: TagFilter

  init(id: UUID = UUID(), name: String, filter: TagFilter) {
    self.id = id
    self.name = name
    self.filter = filter
  }
}

/// 标签巡检结果，方便 UI 展示统计信息
struct TagInspectionSummary: Sendable, Equatable {
  let checkedCount: Int
  let recoveredCount: Int
  let removedCount: Int
  let missingPaths: [String]

  static let empty = TagInspectionSummary(
    checkedCount: 0,
    recoveredCount: 0,
    removedCount: 0,
    missingPaths: []
  )
}
