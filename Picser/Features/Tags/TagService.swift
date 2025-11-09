//
//  TagService.swift
//
//  Created by Eric Cai on 2025/11/08.
//

import Foundation
import Combine

/// 主线程可见的标签服务，负责驱动 UI 状态
@MainActor
final class TagService: ObservableObject {
  static let shared = TagService()

  /// 全局标签列表，按使用频次排序后用于各类 UI 展示
  @Published private(set) var allTags: [TagRecord] = []
  /// 当前作用域（ContentView 图片集合）内的标签统计信息
  @Published private(set) var scopedTags: [ScopedTagSummary] = []
  /// 图片路径到标签列表的映射，用作筛选与推荐的缓存
  @Published private(set) var assignments: [String: [TagRecord]] = [:]
  /// 最近一次巡检的结果，便于在设置页展示
  @Published private(set) var lastInspection: TagInspectionSummary = .empty
  /// 当前激活的筛选条件，驱动内容过滤与 UI 高亮
  @Published var activeFilter: TagFilter = .init()
  /// 最近一次错误文案，直接绑定到 UI 进行提示
  @Published var lastError: String?
  /// 用户自定义的智能筛选集合，变更时同步持久化
  @Published private(set) var smartFilters: [TagSmartFilter] = [] {
    didSet { persistSmartFilters() }
  }

  /// SQLite 仓储层，Actor 保障线程安全
  private let repository = TagRepository.shared
  /// 存储智能筛选的 UserDefaults key
  private let smartFilterStorageKey = "tag.smartFilters"
  private var cancellables: Set<AnyCancellable> = []
  /// 当前生效的图片路径集合，用于计算 scopedTags
  private var scopedPaths: Set<String> = []

  init() {
    loadSmartFilters()
    Task {
      await inspectNow()
      await refreshAllTags()
    }
  }

  /// 重新加载全部标签列表
  func refreshAllTags() async {
    do {
      let tags = try await repository.fetchAllTags()
      allTags = tags
      pruneFilter(availableIDs: Set(tags.map(\.id)))
    } catch {
      lastError = error.localizedDescription
    }
  }

  func purgeUnusedTags() async {
    do {
      try await repository.purgeUnusedTags()
      await refreshAllTags()
    } catch {
      lastError = error.localizedDescription
    }
  }

  /// 刷新当前作用域（ContentView 的图片集合）
  func refreshScope(with urls: [URL]) async {
    let paths = urls.map { $0.standardizedFileURL.path }
    scopedPaths = Set(paths)
    await syncAssignments(for: urls)
    // 作用域内的缓存更新后立刻重建统计，确保筛选面板即时反馈
    rebuildScopedTags()
  }

  /// 同步一批图片的标签信息
  func syncAssignments(for urls: [URL]) async {
    let paths = urls.map { $0.standardizedFileURL.path }
    let pathSet = Set(paths)
    do {
      try await repository.reconcile(urls: urls)
      // 仅保留本次作用域内的缓存，防止 stale 数据影响筛选
      let fetched = try await repository.fetchAssignments(for: paths)
      assignments = assignments.filter { pathSet.contains($0.key) }
      assignments.merge(fetched) { _, new in new }
    } catch {
      lastError = error.localizedDescription
    }
  }

  /// 获取某张图片当前的标签
  func tags(for url: URL) -> [TagRecord] {
    assignments[url.standardizedFileURL.path] ?? []
  }

  func assign(tagNames: [String], to url: URL) async {
    await assign(tagNames: tagNames, to: [url])
  }

  func assign(tagNames: [String], to urls: [URL]) async {
    let trimmedNames = tagNames.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    let normalized = Set(urls.map { $0.standardizedFileURL })
    guard !trimmedNames.isEmpty, !normalized.isEmpty else { return }
    do {
      // 对多张图片逐一写入后再合并回内存缓存，减少 UI 闪烁
      var updatedAssignments: [String: [TagRecord]] = [:]
      for url in normalized {
        let tags = try await repository.assign(tagNames: trimmedNames, to: url)
        updatedAssignments[url.path] = tags
      }
      assignments.merge(updatedAssignments) { _, new in new }
      await refreshAllTags()
      rebuildScopedTags()
    } catch {
      lastError = error.localizedDescription
    }
  }

  func addTags(names: [String]) async {
    let sanitized = names.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    guard !sanitized.isEmpty else { return }
    do {
      try await repository.createTags(names: sanitized)
      await refreshAllTags()
    } catch {
      lastError = error.localizedDescription
    }
  }

  func clearAssignments(for tagIDs: Set<Int64>) async {
    let ids = Array(tagIDs)
    guard !ids.isEmpty else { return }
    do {
      try await repository.removeAllAssignments(for: ids)
      assignments = assignments.mapValues { tags in
        tags.filter { !tagIDs.contains($0.id) }
      }
      await refreshAllTags()
      rebuildScopedTags()
    } catch {
      lastError = error.localizedDescription
    }
  }

  func mergeTags(sourceIDs: Set<Int64>, targetName: String) async {
    let sanitized = targetName.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !sanitized.isEmpty, sourceIDs.count >= 2 else { return }
    do {
      // mergeTags 可能返回已有标签 ID，也可能创建新标签ID
      let targetID = try await repository.mergeTags(sourceIDs: Array(sourceIDs), targetName: sanitized)
      await refreshAllTags()
      await reloadAssignmentsCache()
      rebuildScopedTags()
      if !sourceIDs.contains(targetID) {
        // newly created tag, nothing else to do
      }
    } catch {
      lastError = error.localizedDescription
    }
  }

  func remove(tagID: Int64, from url: URL) async {
    do {
      let tags = try await repository.remove(tagID: tagID, from: url)
      assignments[url.standardizedFileURL.path] = tags
      await refreshAllTags()
      rebuildScopedTags()
    } catch {
      lastError = error.localizedDescription
    }
  }

  func deleteTag(_ tagID: Int64) async {
    do {
      try await repository.deleteTag(tagID)
      await refreshAllTags()
      assignments = assignments.mapValues { tags in
        tags.filter { $0.id != tagID }
      }
      rebuildScopedTags()
    } catch {
      lastError = error.localizedDescription
    }
  }

  func deleteTags(_ tagIDs: Set<Int64>) async {
    guard !tagIDs.isEmpty else { return }
    do {
      try await repository.deleteTags(Array(tagIDs))
      await refreshAllTags()
      assignments = assignments.mapValues { tags in
        tags.filter { !tagIDs.contains($0.id) }
      }
      rebuildScopedTags()
    } catch {
      lastError = error.localizedDescription
    }
  }

  func rename(tagID: Int64, to newName: String) async {
    let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
      lastError = L10n.string("tag_error_invalid_name")
      return
    }
    do {
      try await repository.rename(tagID: tagID, newName: trimmed)
      await refreshAllTags()
      assignments = assignments.mapValues { tags in
        tags.map { tag in
          if tag.id == tagID {
            TagRecord(
              id: tag.id,
              name: trimmed,
              colorHex: tag.colorHex,
              usageCount: tag.usageCount,
              createdAt: tag.createdAt,
              updatedAt: Date()
            )
          } else {
            tag
          }
        }
      }
      rebuildScopedTags()
    } catch {
      lastError = error.localizedDescription
    }
  }

  func updateColor(tagID: Int64, hex: String?) async {
    await updateColor(tagIDs: [tagID], hex: hex)
  }

  func removeAssignments(for paths: [String]) {
    for path in paths {
      assignments.removeValue(forKey: path)
      scopedPaths.remove(path)
    }
    rebuildScopedTags()
  }

  func clearFilter() {
    activeFilter = .init()
  }

  func toggleFilter(tagID: Int64, mode: TagFilterMode = .any) {
    if activeFilter.tagIDs.contains(tagID) {
      activeFilter.tagIDs.remove(tagID)
    } else {
      activeFilter.tagIDs.insert(tagID)
      activeFilter.mode = mode
    }
  }

  func updateKeywordFilter(_ text: String) {
    activeFilter.keyword = text
  }

  func toggleColorFilter(hex: String) {
    guard let normalized = normalizedHex(hex) else { return }
    var sanitized = Set(activeFilter.colorHexes.compactMap { normalizedHex($0) })
    if sanitized.contains(normalized) {
      sanitized.remove(normalized)
    } else {
      sanitized.insert(normalized)
    }
    activeFilter.colorHexes = sanitized
  }

  func clearColorFilters() {
    activeFilter.colorHexes = []
  }

  func applySmartFilter(_ filter: TagSmartFilter) {
    activeFilter = filter.filter
    if let index = smartFilters.firstIndex(where: { $0.id == filter.id }) {
      let applied = smartFilters.remove(at: index)
      smartFilters.insert(applied, at: 0)
    }
  }

  func saveCurrentFilterAsSmart(named name: String) {
    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return }
    guard activeFilter.isActive else { return }
    var sanitized = activeFilter
    sanitized.keyword = sanitized.keyword.trimmingCharacters(in: .whitespacesAndNewlines)
    sanitized.colorHexes = Set(sanitized.colorHexes.compactMap { normalizedHex($0) })

    if let duplicateIndex = smartFilters.firstIndex(where: { $0.filter == sanitized }) {
      smartFilters[duplicateIndex].name = trimmed
      let existing = smartFilters.remove(at: duplicateIndex)
      smartFilters.insert(existing, at: 0)
      return
    }

    if let index = smartFilters.firstIndex(where: {
      $0.name.caseInsensitiveCompare(trimmed) == .orderedSame
    }) {
      smartFilters[index].filter = sanitized
      let updated = smartFilters.remove(at: index)
      smartFilters.insert(updated, at: 0)
    } else {
      let filter = TagSmartFilter(name: trimmed, filter: sanitized)
      smartFilters.insert(filter, at: 0)
    }
  }

  func deleteSmartFilter(id: TagSmartFilter.ID) {
    smartFilters.removeAll { $0.id == id }
  }

  func renameSmartFilter(id: TagSmartFilter.ID, to newName: String) {
    let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return }
    guard let index = smartFilters.firstIndex(where: { $0.id == id }) else { return }
    smartFilters[index].name = trimmed
  }

  func reorderSmartFilters(from source: IndexSet, to destination: Int) {
    guard !source.isEmpty else { return }
    var updated = smartFilters
    let moving = source.sorted().map { smartFilters[$0] }
    for index in source.sorted(by: >) {
      updated.remove(at: index)
    }
    let adjustedDestination = max(
      0,
      min(destination - source.filter { $0 < destination }.count, updated.count)
    )
    updated.insert(contentsOf: moving, at: adjustedDestination)
    smartFilters = updated
  }

  /// 根据当前激活的筛选器过滤图片路径集合
  func filteredImageURLs(from urls: [URL]) -> [URL] {
    guard activeFilter.isActive else { return urls }
    let tagIDs = activeFilter.tagIDs
    let keyword = activeFilter.keyword.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    let hasKeyword = !keyword.isEmpty
    let selectedColors = Set(activeFilter.colorHexes.compactMap { normalizedHex($0) })
    let mode = activeFilter.mode

    return urls.filter { url in
      let normalizedURL = url.standardizedFileURL
      let assignedRecords = assignments[normalizedURL.path] ?? []
      let assignedIDs = Set(assignedRecords.map(\.id))

      if !tagIDs.isEmpty {
        // 针对不同筛选模式分别检验：任意/全部/排除
        let matchesTag: Bool
        switch mode {
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
        // 统一 HEX 大小写后再比较，避免 UI 手动输入造成的误差
        let assignedColors = Set(assignedRecords.compactMap { normalizedHex($0.colorHex) })
        guard !assignedColors.isDisjoint(with: selectedColors) else { return false }
      }

      if hasKeyword {
        // 名称和所在目录都纳入关键字匹配，兼顾文件夹标签化用法
        let lowerName = normalizedURL.lastPathComponent.lowercased()
        let lowerDirectory = normalizedURL.deletingLastPathComponent().lastPathComponent.lowercased()
        guard lowerName.contains(keyword) || lowerDirectory.contains(keyword) else { return false }
      }

      return true
    }
  }

  @MainActor
  func rebuildScopedTags() {
    guard !scopedPaths.isEmpty else {
      scopedTags = []
      if activeFilter.isActive {
        activeFilter = .init()
      }
      return
    }

    // 以标签 ID 为 Key 聚合使用次数，避免重复遍历 collections
    var counts: [Int64: ScopedTagSummary] = [:]
    for path in scopedPaths {
      guard let tags = assignments[path] else { continue }
      for tag in tags {
        var summary = counts[tag.id] ?? ScopedTagSummary(
          id: tag.id,
          name: tag.name,
          colorHex: tag.colorHex,
          usageCount: 0
        )
        summary.usageCount += 1
        counts[tag.id] = summary
      }
    }

    scopedTags = counts.values.sorted {
      if $0.usageCount == $1.usageCount {
        return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
      }
      return $0.usageCount > $1.usageCount
    }

    // 如果筛选器中包含已不在作用域内的标签，需要立即修剪
    pruneFilter(availableIDs: Set(scopedTags.map(\.id)))
    if scopedTags.isEmpty, activeFilter.isActive {
      clearFilter()
    }
  }

  private func pruneFilter(availableIDs: Set<Int64>) {
    guard activeFilter.isActive else { return }
    let filtered = activeFilter.tagIDs.intersection(availableIDs)
    if filtered != activeFilter.tagIDs {
      activeFilter.tagIDs = filtered
    }
  }

  private func reloadAssignmentsCache() async {
    let urls = assignments.keys.map { URL(fileURLWithPath: $0) }
    guard !urls.isEmpty else { return }
    // 使用已有缓存的 Key 触发一次刷新，避免 UI 展示过期的标签颜色/名称
    await syncAssignments(for: urls)
  }

  private func normalizedHex(_ hex: String?) -> String? {
    guard var value = hex?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
      return nil
    }
    if value.hasPrefix("#") {
      value.removeFirst()
    }
    guard !value.isEmpty else { return nil }
    return "#\(value.uppercased())"
  }

  private func loadSmartFilters() {
    guard let data = UserDefaults.standard.data(forKey: smartFilterStorageKey) else { return }
    do {
      let filters = try JSONDecoder().decode([TagSmartFilter].self, from: data)
      smartFilters = filters
    } catch {
      print("Failed to load smart filters: \(error)")
    }
  }

  private func persistSmartFilters() {
    do {
      let data = try JSONEncoder().encode(smartFilters)
      UserDefaults.standard.set(data, forKey: smartFilterStorageKey)
    } catch {
      print("Failed to persist smart filters: \(error)")
    }
  }

  func inspectNow(removeMissing: Bool = true) async {
    do {
      let summary = try await repository.inspectImages(removeMissing: removeMissing)
      lastInspection = summary
      if !summary.missingPaths.isEmpty {
        removeAssignments(for: summary.missingPaths)
      }
    } catch {
      lastError = error.localizedDescription
    }
  }

  func updateColor(tagIDs: Set<Int64>, hex: String?) async {
    guard !tagIDs.isEmpty else { return }
    do {
      try await repository.updateColor(tagIDs: Array(tagIDs), colorHex: hex)
      await refreshAllTags()
      updateCachedAssignmentsColor(tagIDs: tagIDs, hex: hex)
      rebuildScopedTags()
    } catch {
      lastError = error.localizedDescription
    }
  }

  /// 根据同目录文件与当前作用域热度计算推荐标签
  func recommendedTags(for url: URL, limit: Int = 8) -> [TagRecord] {
    let normalized = url.standardizedFileURL
    let assignedIDs = Set(assignments[normalized.path]?.map { $0.id } ?? [])
    let directory = normalized.deletingLastPathComponent().path

    var scores: [Int64: Double] = [:]

    for (path, tags) in assignments {
      guard path != normalized.path else { continue }
      let otherDirectory = URL(fileURLWithPath: path).deletingLastPathComponent().path
      guard otherDirectory == directory else { continue }
      for tag in tags where !assignedIDs.contains(tag.id) {
        // 同目录下已存在的标签给较高基础权重，鼓励目录内风格一致
        scores[tag.id, default: 0] += 2.0
      }
    }

    for summary in scopedTags where !assignedIDs.contains(summary.id) {
      // 再叠加当前视图集合的热度，提升高频标签被推荐的概率
      scores[summary.id, default: 0] += Double(summary.usageCount)
    }

    let index = Dictionary(uniqueKeysWithValues: allTags.map { ($0.id, $0) })
    let sortedIDs = scores.sorted { lhs, rhs in
      if lhs.value == rhs.value {
        let leftName = index[lhs.key]?.name ?? ""
        let rightName = index[rhs.key]?.name ?? ""
        return leftName.localizedCaseInsensitiveCompare(rightName) == .orderedAscending
      }
      return lhs.value > rhs.value
    }.prefix(limit).map { $0.key }

    return sortedIDs.compactMap { index[$0] }
  }

  private func updateCachedAssignmentsColor(tagIDs: Set<Int64>, hex: String?) {
    // 直接在内存缓存中同步颜色，避免等待数据库回读
    assignments = assignments.mapValues { tags in
      tags.map { tag in
        guard tagIDs.contains(tag.id) else { return tag }
        return TagRecord(
          id: tag.id,
          name: tag.name,
          colorHex: hex,
          usageCount: tag.usageCount,
          createdAt: tag.createdAt,
          updatedAt: Date()
        )
      }
    }
  }
}
