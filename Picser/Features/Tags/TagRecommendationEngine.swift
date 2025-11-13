//
//  TagRecommendationEngine.swift
//
//  Created by Eric Cai on 2025/11/10.
//

import Foundation

/// 负责根据上下文计算推荐标签，便于在主服务外独立测试
final class TagRecommendationEngine {
  private let sameDirectoryBoost: Double = 2.0
  private let scopedUsageWeight: Double = 0.9
  private let directoryUsageWeight: Double = 0.6
  private let telemetry: TagRecommendationTelemetry

  init(telemetry: TagRecommendationTelemetry = .shared) {
    self.telemetry = telemetry
  }

  func recommendedTags(
    for url: URL,
    assignments: [String: [TagRecord]],
    scopedTags: [ScopedTagSummary],
    allTags: [TagRecord],
    directoryStats: [Int64: Int],
    limit: Int
  ) -> [TagRecord] {
    guard limit > 0, !allTags.isEmpty else { return [] }

    let normalized = url.standardizedFileURL
    let assignedIDs = Set(assignments[normalized.path]?.map { $0.id } ?? [])
    let availableTags = allTags.filter { !assignedIDs.contains($0.id) }
    guard !availableTags.isEmpty else { return [] }
    let directory = normalized.deletingLastPathComponent().path
    let scopeSignature = scopedTags.hashValue
    let context = TagRecommendationContext(
      imagePath: normalized.path,
      directory: directory,
      scopeSignature: scopeSignature
    )
    let index = Dictionary(uniqueKeysWithValues: allTags.map { ($0.id, $0) })

    var scores: [Int64: Double] = [:]

    for (path, tags) in assignments {
      guard path != normalized.path else { continue }
      let otherDirectory = URL(fileURLWithPath: path).deletingLastPathComponent().path
      guard otherDirectory == directory else { continue }
      for tag in tags where !assignedIDs.contains(tag.id) {
        // 同目录下已存在的标签给较高基础权重，鼓励目录内风格一致
        scores[tag.id, default: 0] += sameDirectoryBoost
      }
    }

    for summary in scopedTags where !assignedIDs.contains(summary.id) {
      // 使用 log1p 缓冲超大数字的影响，避免单个热门标签压制其它候选项
      let contribution = log1p(Double(summary.usageCount)) * scopedUsageWeight
      scores[summary.id, default: 0] += contribution
    }

    for (tagID, usage) in directoryStats where !assignedIDs.contains(tagID) {
      let contribution = log1p(Double(usage)) * directoryUsageWeight
      scores[tagID, default: 0] += contribution
    }

    if scores.isEmpty {
      return Array(availableTags.sorted(by: localeAwareAscending).prefix(limit))
    }

    let filteredScores = scores.filter { index[$0.key] != nil }
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

    var candidates = sortedIDs.compactMap { index[$0] }
    if candidates.count < limit {
      let missing = limit - candidates.count
      let fallbackPool = availableTags.filter { !sortedIDs.contains($0.id) }
      let fallback = Array(fallbackPool.sorted(by: localeAwareAscending).prefix(missing))
      candidates += fallback
    }
    Task {
      await telemetry.recordServed(tagIDs: candidates.map(\.id), context: context)
    }
    return candidates
  }

  private func localeAwareAscending(_ lhs: TagRecord, _ rhs: TagRecord) -> Bool {
    lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
  }
}
