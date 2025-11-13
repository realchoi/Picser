//
//  TagAssignmentCache.swift
//
//  Created by Eric Cai on 2025/11/10.
//

import Foundation

/// 管理图片路径与标签的缓存，并跟踪版本、作用域路径等信息。
@MainActor
final class TagAssignmentCache: ObservableObject {
  @Published private(set) var assignments: [String: [TagRecord]] = [:]
  @Published private(set) var scopedTags: [ScopedTagSummary] = []
  private(set) var scopedPaths: Set<String> = []
  private(set) var version: Int = 0
  private var scopedCounts: [Int64: ScopedTagSummary] = [:]

  func tags(for url: URL) -> [TagRecord] {
    assignments[url.standardizedFileURL.path] ?? []
  }

  /// 同步作用域路径集合
  ///
  /// 当用户选择的图片集合发生变化时调用，更新作用域统计信息。
  /// 如果新路径集合与旧路径集合相同，则跳过更新以提高性能。
  ///
  /// - Parameter urls: 新的图片 URL 集合
  func syncScopedPaths(with urls: [URL]) {
    let newPaths = Set(urls.map { $0.standardizedFileURL.path })
    guard newPaths != scopedPaths else { return }
    scopedPaths = newPaths
    rebuildScopedCounts()
    refreshScopedSnapshot()
  }

  /// 替换所有缓存数据
  ///
  /// 用于初始加载或全量刷新场景。会触发版本号更新和作用域统计重建。
  ///
  /// - Parameter newAssignments: 新的完整映射关系
  func replaceAll(with newAssignments: [String: [TagRecord]]) {
    assignments = newAssignments
    bumpVersion()
    rebuildScopedCounts()
    refreshScopedSnapshot()
  }

  /// 增量更新标签分配
  ///
  /// 使用增量策略更新缓存，只处理真正发生变化的图片。
  /// 对于每个变化的图片，使用 applyDelta 方法增量更新作用域统计，
  /// 避免全量重建，提高性能。
  ///
  /// 优化策略：
  /// 1. 跳过未发生变化的图片（oldTags == newTags）
  /// 2. 只在有实际变化时才更新版本号和刷新快照
  ///
  /// - Parameter updates: 路径到新标签列表的映射
  func updateAssignments(_ updates: [String: [TagRecord]]) {
    guard !updates.isEmpty else { return }
    var requiresSnapshot = false
    for (path, newTags) in updates {
      let key = path
      let oldTags = assignments[key] ?? []
      // 跳过未变化的图片，减少不必要的计算
      if oldTags == newTags {
        continue
      }
      // 更新或移除映射关系
      if newTags.isEmpty {
        assignments.removeValue(forKey: key)
      } else {
        assignments[key] = newTags
      }
      // 增量更新作用域统计
      applyDelta(for: key, oldTags: oldTags, newTags: newTags)
      requiresSnapshot = true
    }
    if requiresSnapshot {
      bumpVersion()
      refreshScopedSnapshot()
    }
  }

  /// 移除指定路径的缓存数据
  ///
  /// 批量移除图片的标签映射关系，并增量更新作用域统计。
  /// 用于图片被删除或移出作用域的场景。
  ///
  /// - Parameter paths: 要移除的图片路径列表
  func remove(paths: [String]) {
    guard !paths.isEmpty else { return }
    var didChange = false
    for path in paths {
      scopedPaths.remove(path)
      let oldTags = assignments.removeValue(forKey: path) ?? []
      guard !oldTags.isEmpty else { continue }
      // 将标签移除视为 oldTags -> []，增量更新统计
      applyDelta(for: path, oldTags: oldTags, newTags: [])
      didChange = true
    }
    if didChange {
      bumpVersion()
      refreshScopedSnapshot()
    }
  }

  /// 重建作用域标签统计
  ///
  /// 当作用域路径发生重大变化时，可以调用此方法强制重建统计信息。
  /// 通常在 syncScopedPaths 中自动调用，很少需要手动调用。
  func rebuildScopedTags() {
    rebuildScopedCounts()
    refreshScopedSnapshot()
  }

  /// 从头重建作用域标签计数
  ///
  /// 遍历作用域内所有图片，统计每个标签的使用次数。
  /// 时间复杂度：O(n * m)，其中 n 是作用域内图片数量，m 是平均每张图片的标签数量
  ///
  /// 算法步骤：
  /// 1. 如果作用域为空，清空计数并返回
  /// 2. 遍历作用域内每张图片的标签
  /// 3. 首次遇到的标签：创建新的 ScopedTagSummary
  /// 4. 已存在的标签：仅增加 usageCount 计数
  private func rebuildScopedCounts() {
    guard !scopedPaths.isEmpty else {
      scopedCounts = [:]
      return
    }
    var counts: [Int64: ScopedTagSummary] = [:]
    for path in scopedPaths {
      guard let tags = assignments[path] else { continue }
      for tag in tags {
        if let existing = counts[tag.id] {
          // 已存在：仅更新计数
          var updated = existing
          updated.usageCount += 1
          counts[tag.id] = updated
        } else {
          // 首次出现：创建新 summary
          counts[tag.id] = ScopedTagSummary(
            id: tag.id,
            name: tag.name,
            colorHex: tag.colorHex,
            usageCount: 1
          )
        }
      }
    }
    scopedCounts = counts
  }

  /// 刷新作用域标签快照
  ///
  /// 将 scopedCounts 字典转换为排序后的数组，供 UI 展示使用。
  ///
  /// 排序规则：
  /// 1. 按使用频次降序排列（热门标签在前）
  /// 2. 使用频次相同时，按名称字母序升序排列
  ///
  /// 时间复杂度：O(n log n)，其中 n 是作用域内不同标签的数量
  private func refreshScopedSnapshot() {
    guard !scopedPaths.isEmpty else {
      scopedTags = []
      return
    }
    scopedTags = scopedCounts.values.sorted {
      if $0.usageCount == $1.usageCount {
        return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
      }
      return $0.usageCount > $1.usageCount
    }
  }

  /// 增量更新作用域标签计数
  ///
  /// 核心增量更新算法，避免全量重建 scopedCounts。
  /// 通过计算 oldTags 和 newTags 的差异，仅更新受影响的标签统计。
  ///
  /// 算法步骤：
  /// 1. 检查图片是否在作用域内，不在作用域内则跳过
  /// 2. 计算标签增减变化（diff[tagID] = +1 表示新增，-1 表示移除）
  /// 3. 应用变化到 scopedCounts：
  ///    - 标签被完全移除（usageCount <= 0）：从字典中删除
  ///    - 标签仍在使用：更新计数和元数据
  ///
  /// 时间复杂度：O(m + n)，其中 m 是 oldTags 数量，n 是 newTags 数量
  ///
  /// - Parameters:
  ///   - path: 图片路径
  ///   - oldTags: 更新前的标签列表
  ///   - newTags: 更新后的标签列表
  private func applyDelta(for path: String, oldTags: [TagRecord], newTags: [TagRecord]) {
    // 只处理作用域内的图片
    guard scopedPaths.contains(path) else { return }
    if oldTags.isEmpty, newTags.isEmpty { return }

    // 计算标签 ID 的增减变化
    var diff: [Int64: Int] = [:]
    for tag in oldTags {
      diff[tag.id, default: 0] -= 1  // 旧标签计数 -1
    }
    for tag in newTags {
      diff[tag.id, default: 0] += 1  // 新标签计数 +1
    }

    // 应用变化到 scopedCounts
    for (id, delta) in diff where delta != 0 {
      var summary = scopedCounts[id] ?? ScopedTagSummary(
        id: id,
        name: "",
        colorHex: nil,
        usageCount: 0
      )
      summary.usageCount += delta

      // 如果计数降为 0 或负数，从字典中移除
      if summary.usageCount <= 0 {
        scopedCounts.removeValue(forKey: id)
        continue
      }

      // 更新标签元数据（名称和颜色）
      // 优先使用 newTags 中的数据，如果不存在则使用 oldTags
      if let updated = newTags.first(where: { $0.id == id })
        ?? oldTags.first(where: { $0.id == id }) {
        summary.name = updated.name
        summary.colorHex = updated.colorHex
      }
      scopedCounts[id] = summary
    }
  }

  /// 增加版本号
  ///
  /// 使用溢出加法（&+），避免在极少数情况下的整数溢出问题。
  /// 版本号用于标识缓存数据的变化，用于缓存失效判断。
  private func bumpVersion() {
    version &+= 1
  }
}
