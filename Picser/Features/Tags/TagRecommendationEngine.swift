//
//  TagRecommendationEngine.swift
//
//  Created by Eric Cai on 2025/11/10.
//

import Foundation

/// 标签推荐引擎
///
/// 根据多种上下文信号为图片推荐合适的标签，便于在主服务外独立测试。
///
/// 推荐策略：
/// 1. **同目录优先**：同目录下其他图片已使用的标签获得更高权重
/// 2. **作用域热度**：当前选中图片集合中使用频率高的标签
/// 3. **目录统计**：图片所在目录的历史标签使用统计
///
/// 权重设计：
/// - sameDirectoryBoost (2.0)：同目录下已存在的标签基础权重
/// - scopedUsageWeight (0.9)：作用域内标签使用频次的权重系数
/// - directoryUsageWeight (0.6)：目录历史统计的权重系数
///
/// 使用对数缓冲（log1p）处理使用频次，避免极热门标签压制其他候选项。
final class TagRecommendationEngine {
  /// 同目录标签的基础权重加成
  /// 最高权重，确保同目录风格一致性
  private let sameDirectoryBoost: Double = 2.0

  /// 作用域内标签使用频次的权重系数
  /// 次高权重，反映当前工作上下文
  private let scopedUsageWeight: Double = 0.9

  /// 目录历史统计的权重系数
  /// 最低权重，作为辅助参考
  private let directoryUsageWeight: Double = 0.6

  /// 初始化推荐引擎
  init() {}

  /// 为指定图片推荐标签
  ///
  /// 推荐算法：
  /// 1. 过滤已分配的标签，只推荐未使用的标签
  /// 2. 计算每个候选标签的综合得分：
  ///    - 同目录权重：如果标签在同目录其他图片中出现，得分 += 2.0
  ///    - 作用域权重：得分 += log1p(作用域使用次数) * 0.9
  ///    - 目录统计权重：得分 += log1p(目录使用次数) * 0.6
  /// 3. 按得分降序排列，得分相同时按名称字母序排列
  /// 4. 如果得分标签不足，用字母序补充到指定数量
  ///
  /// 为什么使用 log1p：
  /// - 防止极热门标签（使用次数非常大）完全压制其他候选标签
  /// - 例如：使用 100 次的标签得分 ≈ 4.6，使用 1000 次的得分 ≈ 6.9，差距被缩小
  /// - log1p(x) = log(1 + x)，避免 log(0) 的问题
  ///
  /// - Parameters:
  ///   - url: 目标图片 URL
  ///   - assignments: 所有图片的标签分配关系
  ///   - scopedTags: 当前作用域的标签统计信息
  ///   - allTags: 全局可用的所有标签
  ///   - directoryStats: 图片所在目录的标签使用统计
  ///   - limit: 推荐标签的最大数量
  /// - Returns: 推荐的标签列表，按优先级降序排列
  func recommendedTags(
    for url: URL,
    assignments: [String: [TagRecord]],
    scopedTags: [ScopedTagSummary],
    allTags: [TagRecord],
    directoryStats: [Int64: Int],
    limit: Int
  ) -> [TagRecord] {
    guard limit > 0, !allTags.isEmpty else { return [] }

    // 获取图片已分配的标签 ID
    let normalized = url.standardizedFileURL
    let assignedIDs = Set(assignments[normalized.path]?.map { $0.id } ?? [])

    // 过滤出未分配的可用标签
    let availableTags = allTags.filter { !assignedIDs.contains($0.id) }
    guard !availableTags.isEmpty else { return [] }

    let directory = normalized.deletingLastPathComponent().path

    // 构建标签 ID 到标签对象的索引
    let index = Dictionary(uniqueKeysWithValues: allTags.map { ($0.id, $0) })

    var scores: [Int64: Double] = [:]

    // 1. 计算同目录标签权重
    for (path, tags) in assignments {
      guard path != normalized.path else { continue }
      let otherDirectory = URL(fileURLWithPath: path).deletingLastPathComponent().path
      guard otherDirectory == directory else { continue }
      for tag in tags where !assignedIDs.contains(tag.id) {
        // 同目录下已存在的标签给较高基础权重，鼓励目录内风格一致
        scores[tag.id, default: 0] += sameDirectoryBoost
      }
    }

    // 2. 计算作用域标签权重
    for summary in scopedTags where !assignedIDs.contains(summary.id) {
      // 使用 log1p 缓冲超大数字的影响，避免单个热门标签压制其它候选项
      let contribution = log1p(Double(summary.usageCount)) * scopedUsageWeight
      scores[summary.id, default: 0] += contribution
    }

    // 3. 计算目录统计权重
    for (tagID, usage) in directoryStats where !assignedIDs.contains(tagID) {
      let contribution = log1p(Double(usage)) * directoryUsageWeight
      scores[tagID, default: 0] += contribution
    }

    // 如果没有任何得分数据，返回字母序前 N 个标签
    if scores.isEmpty {
      return Array(availableTags.sorted(by: localeAwareAscending).prefix(limit))
    }

    // 过滤出仍然存在于全局标签列表中的候选项
    let filteredScores = scores.filter { index[$0.key] != nil }

    // 按得分降序排列，得分相同时按名称字母序排列
    let sortedIDs = filteredScores
      .sorted { lhs, rhs in
        if lhs.value == rhs.value {
          let leftName = index[lhs.key]?.name ?? ""
          let rightName = index[rhs.key]?.name ?? ""
          return leftName.localizedCaseInsensitiveCompare(rightName) == .orderedAscending
        }
        return lhs.value > rhs.value
      }
      .prefix(limit)
      .map(\.key)

    // 构建推荐结果
    var candidates = sortedIDs.compactMap { index[$0] }

    // 如果推荐标签不足，用字母序补充
    if candidates.count < limit {
      let missing = limit - candidates.count
      let fallbackPool = availableTags.filter { !sortedIDs.contains($0.id) }
      let fallback = Array(fallbackPool.sorted(by: localeAwareAscending).prefix(missing))
      candidates += fallback
    }



    return candidates
  }

  /// 本地化字母序比较函数
  ///
  /// 使用不区分大小写的本地化比较，确保标签排序符合用户语言习惯。
  /// 例如：中文按拼音排序，英文按字母序排序。
  ///
  /// - Parameters:
  ///   - lhs: 左侧标签
  ///   - rhs: 右侧标签
  /// - Returns: 如果 lhs 应该排在 rhs 前面，返回 true
  private func localeAwareAscending(_ lhs: TagRecord, _ rhs: TagRecord) -> Bool {
    lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
  }
}
