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

  func syncScopedPaths(with urls: [URL]) {
    let newPaths = Set(urls.map { $0.standardizedFileURL.path })
    guard newPaths != scopedPaths else { return }
    scopedPaths = newPaths
    rebuildScopedCounts()
    refreshScopedSnapshot()
  }

  func replaceAll(with newAssignments: [String: [TagRecord]]) {
    assignments = newAssignments
    bumpVersion()
    rebuildScopedCounts()
    refreshScopedSnapshot()
  }

  func updateAssignments(_ updates: [String: [TagRecord]]) {
    guard !updates.isEmpty else { return }
    var requiresSnapshot = false
    for (path, newTags) in updates {
      let key = path
      let oldTags = assignments[key] ?? []
      if oldTags == newTags {
        continue
      }
      if newTags.isEmpty {
        assignments.removeValue(forKey: key)
      } else {
        assignments[key] = newTags
      }
      applyDelta(for: key, oldTags: oldTags, newTags: newTags)
      requiresSnapshot = true
    }
    if requiresSnapshot {
      bumpVersion()
      refreshScopedSnapshot()
    }
  }

  func remove(paths: [String]) {
    guard !paths.isEmpty else { return }
    var didChange = false
    for path in paths {
      scopedPaths.remove(path)
      let oldTags = assignments.removeValue(forKey: path) ?? []
      guard !oldTags.isEmpty else { continue }
      applyDelta(for: path, oldTags: oldTags, newTags: [])
      didChange = true
    }
    if didChange {
      bumpVersion()
      refreshScopedSnapshot()
    }
  }

  func rebuildScopedTags() {
    rebuildScopedCounts()
    refreshScopedSnapshot()
  }

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

  private func applyDelta(for path: String, oldTags: [TagRecord], newTags: [TagRecord]) {
    guard scopedPaths.contains(path) else { return }
    if oldTags.isEmpty, newTags.isEmpty { return }
    var diff: [Int64: Int] = [:]
    for tag in oldTags {
      diff[tag.id, default: 0] -= 1
    }
    for tag in newTags {
      diff[tag.id, default: 0] += 1
    }
    for (id, delta) in diff where delta != 0 {
      var summary = scopedCounts[id] ?? ScopedTagSummary(
        id: id,
        name: "",
        colorHex: nil,
        usageCount: 0
      )
      summary.usageCount += delta
      if summary.usageCount <= 0 {
        scopedCounts.removeValue(forKey: id)
        continue
      }
      if let updated = newTags.first(where: { $0.id == id })
        ?? oldTags.first(where: { $0.id == id }) {
        summary.name = updated.name
        summary.colorHex = updated.colorHex
      }
      scopedCounts[id] = summary
    }
  }

  private func bumpVersion() {
    version &+= 1
  }
}
