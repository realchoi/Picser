//
//  TagFilterManager.swift
//
//  Created by Eric Cai on 2025/11/10.
//

import Foundation

/// 管理标签筛选逻辑与结果缓存，减少重复计算
actor TagFilterManager {
  private struct Cache {
    let filter: TagFilter
    let urlsHash: Int
    let assignmentsVersion: Int
    let result: [URL]
  }

  private var cache: Cache?

  /// 根据当前筛选条件过滤图片集合，并使用 assignmentsVersion 作为变更指纹
  func filteredImageURLs(
    filter: TagFilter,
    urls: [URL],
    assignments: [String: [TagRecord]],
    assignmentsVersion: Int
  ) -> [URL] {
    guard filter.isActive else {
      cache = Cache(
        filter: filter,
        urlsHash: hash(urls: urls),
        assignmentsVersion: assignmentsVersion,
        result: urls
      )
      return urls
    }

    let urlsHash = hash(urls: urls)
    if let cache,
       cache.filter == filter,
       cache.urlsHash == urlsHash,
       cache.assignmentsVersion == assignmentsVersion {
      return cache.result
    }

    let keyword = filter.keyword.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    let hasKeyword = !keyword.isEmpty
    let tagIDs = filter.tagIDs
    let selectedColors = Set(filter.colorHexes.compactMap { $0.normalizedHexColor() })

    let filtered = urls.filter { url in
      let normalizedURL = url.standardizedFileURL
      let assignedRecords = assignments[normalizedURL.path] ?? []
      let assignedIDs = Set(assignedRecords.map(\.id))

      if !tagIDs.isEmpty {
        let matchesTag: Bool
        switch filter.mode {
        case .any:
          matchesTag = !assignedIDs.isDisjoint(with: tagIDs)
        case .all:
          matchesTag = tagIDs.isSubset(of: assignedIDs)
        case .exclude:
          matchesTag = assignedIDs.isDisjoint(with: tagIDs)
        }
        guard matchesTag else { return false }
      }

      if !selectedColors.isEmpty {
        let assignedColors = Set(assignedRecords.compactMap { $0.colorHex.normalizedHexColor() })
        guard !assignedColors.isDisjoint(with: selectedColors) else { return false }
      }

      if hasKeyword {
        let lowerName = normalizedURL.lastPathComponent.lowercased()
        let lowerDirectory = normalizedURL.deletingLastPathComponent().lastPathComponent.lowercased()
        guard lowerName.contains(keyword) || lowerDirectory.contains(keyword) else { return false }
      }

      return true
    }

    cache = Cache(
      filter: filter,
      urlsHash: urlsHash,
      assignmentsVersion: assignmentsVersion,
      result: filtered
    )
    return filtered
  }

  /// 主动使缓存失效
  func invalidateCache() {
    cache = nil
  }

  /// 根据当前作用域的标签 ID 修剪筛选条件
  static func prunedFilter(_ filter: TagFilter, availableIDs: Set<Int64>) -> TagFilter {
    guard filter.isActive else { return filter }
    var sanitized = filter
    sanitized.tagIDs = filter.tagIDs.intersection(availableIDs)
    return sanitized
  }

  private func hash(urls: [URL]) -> Int {
    var hasher = Hasher()
    hasher.combine(urls.count)
    for url in urls {
      hasher.combine(url.standardizedFileURL.path)
    }
    return hasher.finalize()
  }
}
