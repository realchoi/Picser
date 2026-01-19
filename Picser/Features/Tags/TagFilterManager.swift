//
//  TagFilterManager.swift
//
//  Created by Eric Cai on 2025/11/10.
//

import Foundation

/// 管理标签筛选逻辑与结果缓存，减少重复计算
///
/// 核心职责：
/// 1. 根据筛选条件过滤图片集合
/// 2. 缓存筛选结果，避免重复计算
/// 3. 智能检测缓存失效条件
///
/// 缓存失效条件：
/// - 筛选条件变化（filter 对象不同）
/// - 输入图片集合变化（urls 的哈希值不同）
/// - 标签分配关系变化（assignmentsVersion 不同）
///
/// 线程安全：使用 actor 隔离确保并发安全
actor TagFilterManager {
  /// 缓存结构，包含完整的筛选上下文和结果
  private struct Cache {
    /// 筛选条件
    let filter: TagFilter
    /// 输入图片集合的哈希值
    let urlsHash: Int
    /// 标签分配关系的版本号
    let assignmentsVersion: Int
    /// 筛选结果
    let result: [URL]
  }

  private var cache: Cache?

  /// 根据当前筛选条件过滤图片集合
  ///
  /// 筛选逻辑：
  /// 1. 标签筛选（tagIDs）：
  ///    - any 模式：图片至少有一个指定标签
  ///    - all 模式：图片必须有所有指定标签
  ///    - exclude 模式：图片不能有任何指定标签
  /// 2. 颜色筛选（colorHexes）：图片至少有一个指定颜色的标签
  /// 3. 关键词筛选（keyword）：图片文件名或所在目录名包含关键词
  ///
  /// 缓存策略：
  /// - 如果筛选器未激活（!filter.isActive），直接返回所有图片并缓存
  /// - 如果缓存命中且上下文未变化，直接返回缓存结果
  /// - 否则执行筛选逻辑并更新缓存
  ///
  /// - Parameters:
  ///   - filter: 筛选条件
  ///   - urls: 待筛选的图片 URL 集合
  ///   - assignments: 图片路径到标签列表的映射
  ///   - assignmentsVersion: 标签分配关系的版本号，用于缓存失效判断
  /// - Returns: 符合筛选条件的图片 URL 数组
  func filteredImageURLs(
    filter: TagFilter,
    urls: [URL],
    assignments: [String: [TagRecord]],
    assignmentsVersion: Int
  ) -> [URL] {
    // 快速路径：筛选器未激活，返回所有图片
    guard filter.isActive else {
      cache = Cache(
        filter: filter,
        urlsHash: hash(urls: urls),
        assignmentsVersion: assignmentsVersion,
        result: urls
      )
      return urls
    }

    // 检查缓存是否命中
    let urlsHash = hash(urls: urls)
    if let cache,
       cache.filter == filter,
       cache.urlsHash == urlsHash,
       cache.assignmentsVersion == assignmentsVersion {
      return cache.result
    }

    // 预处理筛选条件
    let keyword = filter.keyword.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    let hasKeyword = !keyword.isEmpty
    let tagIDs = filter.tagIDs
    let selectedColors = Set(filter.colorHexes.compactMap { $0.normalizedHexColor() })
    let requiresColorMatch = !selectedColors.isEmpty

    // 本次筛选内的轻量缓存，避免反复构建集合
    var tagIDCache: [String: Set<Int64>] = [:]
    var colorCache: [String: Set<String>] = [:]

    // 执行筛选逻辑
    let filtered = urls.filter { url in
      let normalizedURL = url.standardizedFileURL
      let path = normalizedURL.path
      let assignedRecords = assignments[path] ?? []
      let assignedIDs: Set<Int64>
      if let cached = tagIDCache[path] {
        assignedIDs = cached
      } else {
        let built = Set(assignedRecords.map(\.id))
        tagIDCache[path] = built
        assignedIDs = built
      }

      // 1. 标签筛选
      if !tagIDs.isEmpty {
        let matchesTag: Bool
        switch filter.mode {
        case .any:
          // any 模式：图片至少有一个指定标签
          matchesTag = !assignedIDs.isDisjoint(with: tagIDs)
        case .all:
          // all 模式：图片必须有所有指定标签
          matchesTag = tagIDs.isSubset(of: assignedIDs)
        case .exclude:
          // exclude 模式：图片不能有任何指定标签
          matchesTag = assignedIDs.isDisjoint(with: tagIDs)
        }
        guard matchesTag else { return false }
      }

      // 2. 颜色筛选：图片至少有一个指定颜色的标签
      if requiresColorMatch {
        let assignedColors: Set<String>
        if let cached = colorCache[path] {
          assignedColors = cached
        } else {
          let built = Set(assignedRecords.compactMap { $0.colorHex.normalizedHexColor() })
          colorCache[path] = built
          assignedColors = built
        }
        guard !assignedColors.isDisjoint(with: selectedColors) else { return false }
      }

      // 3. 关键词筛选：文件名或目录名包含关键词
      if hasKeyword {
        let lowerName = normalizedURL.lastPathComponent.lowercased()
        let lowerDirectory = normalizedURL.deletingLastPathComponent().lastPathComponent.lowercased()
        guard lowerName.contains(keyword) || lowerDirectory.contains(keyword) else { return false }
      }

      return true
    }

    // 更新缓存
    cache = Cache(
      filter: filter,
      urlsHash: urlsHash,
      assignmentsVersion: assignmentsVersion,
      result: filtered
    )
    return filtered
  }

  /// 主动使缓存失效
  ///
  /// 在标签数据发生重大变化时调用，强制下次筛选重新计算。
  func invalidateCache() {
    cache = nil
  }

  /// 根据当前作用域的可用标签 ID 修剪筛选条件
  ///
  /// 移除筛选条件中不在作用域内的标签 ID，避免无效筛选。
  /// 例如：如果用户选择了标签 A、B、C，但当前作用域内只有标签 A 和 B，
  /// 则修剪后的筛选条件只包含标签 A 和 B。
  ///
  /// - Parameters:
  ///   - filter: 原始筛选条件
  ///   - availableIDs: 当前作用域内可用的标签 ID 集合
  /// - Returns: 修剪后的筛选条件
  static func prunedFilter(_ filter: TagFilter, availableIDs: Set<Int64>) -> TagFilter {
    guard filter.isActive else { return filter }
    var sanitized = filter
    sanitized.tagIDs = filter.tagIDs.intersection(availableIDs)
    return sanitized
  }

  /// 计算图片 URL 数组的哈希值
  ///
  /// 使用数组长度和每个 URL 的标准化路径计算哈希值。
  /// 用于快速检测图片集合是否发生变化。
  ///
  /// - Parameter urls: 图片 URL 数组
  /// - Returns: 哈希值
  private func hash(urls: [URL]) -> Int {
    var hasher = Hasher()
    hasher.combine(urls.count)
    for url in urls {
      hasher.combine(url.standardizedFileURL.path)
    }
    return hasher.finalize()
  }
}
