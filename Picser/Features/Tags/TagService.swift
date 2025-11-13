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
  @Published var activeFilter: TagFilter = .init() {
    didSet {
      if oldValue != activeFilter {
        Task { await filterManager.invalidateCache() }
      }
    }
  }
  /// 最近一次错误文案，直接绑定到 UI 进行提示
  @Published private(set) var lastError: String?
  /// 最新的操作反馈事件，带有提示类型与时间戳
  @Published private(set) var feedbackEvent: TagOperationFeedback?
  /// 用户自定义的智能筛选集合
  @Published private(set) var smartFilters: [TagSmartFilter] = []

  /// SQLite 仓储层，Actor 保障线程安全
  private let repository = TagRepository.shared
  private let filterManager = TagFilterManager()
  private let recommendationEngine = TagRecommendationEngine()
  private let directoryStatsCache = DirectoryTagStatsCache(maxEntries: 200)
  private let smartFilterStore = TagSmartFilterStore()
  private var cancellables: Set<AnyCancellable> = []
  /// 缓存图片标签映射与作用域信息
  private let assignmentCache = TagAssignmentCache()
  var assignmentsVersion: Int { assignmentCache.version }
  @Published private(set) var allTagsSortedByName: [TagRecord] = []
  @Published private(set) var feedbackHistory: [TagOperationFeedback] = []
  /// 控制全量标签刷新频率的调度参数（纳秒）
  private let refreshDebounceInterval: UInt64 = 250_000_000
  /// 延迟触发的刷新任务
  private var scheduledRefreshTask: Task<Void, Never>?
  /// 正在执行的刷新循环任务
  private var refreshLoopTask: Task<Void, Never>?
  /// 是否存在待处理的刷新请求（用于合并高频调用）
  private var pendingRefreshRequest = false

  init() {
    smartFilterStore.$filters
      .receive(on: RunLoop.main)
      .assign(to: &$smartFilters)
    assignmentCache.$assignments
      .receive(on: RunLoop.main)
      .sink { [weak self] newValue in
        guard let self else { return }
        self.assignments = newValue
        Task { await self.filterManager.invalidateCache() }
      }
      .store(in: &cancellables)
    assignmentCache.$scopedTags
      .receive(on: RunLoop.main)
      .assign(to: &$scopedTags)

    Task {
      await inspectNow()
      await refreshAllTags(immediate: true)
    }
  }

  /// 重新加载全部标签列表，可选择立即执行或合并为延迟刷新
  func refreshAllTags(immediate: Bool = false) async {
    if immediate {
      let task = startImmediateRefresh()
      await task.value
    } else {
      scheduleCoalescedRefresh()
    }
  }

  private func startImmediateRefresh() -> Task<Void, Never> {
    pendingRefreshRequest = true
    cancelScheduledRefresh()
    if let refreshLoopTask {
      return refreshLoopTask
    }
    let task = Task { [weak self] in
      guard let self else { return }
      await self.runRefreshLoop()
    }
    refreshLoopTask = task
    return task
  }

  private func scheduleCoalescedRefresh() {
    pendingRefreshRequest = true
    guard refreshLoopTask == nil else { return }
    guard scheduledRefreshTask == nil else { return }
    let interval = refreshDebounceInterval
    scheduledRefreshTask = Task { [weak self] in
      do {
        try await Task.sleep(nanoseconds: interval)
      } catch {
        return
      }
      await MainActor.run { [weak self] in
        guard let self else { return }
        self.scheduledRefreshTask = nil
        if self.refreshLoopTask == nil {
          self.refreshLoopTask = Task { [weak self] in
            guard let self else { return }
            await self.runRefreshLoop()
          }
        }
      }
    }
  }

  private func cancelScheduledRefresh() {
    scheduledRefreshTask?.cancel()
    scheduledRefreshTask = nil
  }

  private func runRefreshLoop() async {
    defer { refreshLoopTask = nil }
    repeat {
      pendingRefreshRequest = false
      await performRefreshAllTags()
    } while pendingRefreshRequest
  }

  private func performRefreshAllTags() async {
    do {
      let tags = try await repository.fetchAllTags()
      allTags = tags
      allTagsSortedByName = tags.sorted {
        $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
      }
      pruneFilter(availableIDs: Set(tags.map(\.id)))
      lastError = nil
    } catch {
      recordError(error)
    }
  }

  func purgeUnusedTags() async {
    do {
      try await repository.purgeUnusedTags()
      await refreshAllTags()
      lastError = nil
    } catch {
      recordError(error)
    }
  }

  /// 刷新当前作用域（ContentView 的图片集合）
  func refreshScope(with urls: [URL]) async {
    assignmentCache.syncScopedPaths(with: urls)
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
      var updated = assignmentCache.assignments.filter { pathSet.contains($0.key) }
      updated.merge(fetched) { _, new in new }
      assignmentCache.replaceAll(with: updated)
      invalidateDirectoryCaches(forPaths: Array(updated.keys))
      if pathSet.isEmpty {
        lastError = nil
      } else {
        recordSuccess(key: "tag_feedback_sync_success", arguments: [pathSet.count])
      }
    } catch {
      let message = String(
        format: L10n.string("tag_feedback_sync_failure"),
        error.localizedDescription
      )
      recordError(message: message)
    }
  }

  /// 获取某张图片当前的标签
  func tags(for url: URL) -> [TagRecord] {
    assignmentCache.tags(for: url)
  }

  func assign(tagNames: [String], to url: URL) async {
    await assign(tagNames: tagNames, to: [url])
  }

  func assign(tagNames: [String], to urls: [URL]) async {
    let trimmedNames = tagNames.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    let normalized = Array(Set(urls.map { $0.standardizedFileURL }))
    guard !trimmedNames.isEmpty, !normalized.isEmpty else { return }
    do {
      let updatedAssignments = try await repository.assign(tagNames: trimmedNames, to: normalized)
      assignmentCache.updateAssignments(updatedAssignments)
      invalidateDirectoryCaches(forPaths: Array(updatedAssignments.keys))
      await refreshAllTags()
      rebuildScopedTags()
      lastError = nil
    } catch {
      recordError(error)
    }
  }

  func addTags(names: [String]) async {
    let sanitized = names.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    guard !sanitized.isEmpty else { return }
    do {
      try await repository.createTags(names: sanitized)
      await refreshAllTags()
      lastError = nil
    } catch {
      recordError(error)
    }
  }

  func clearAssignments(for tagIDs: Set<Int64>) async {
    let ids = Array(tagIDs)
    guard !ids.isEmpty else { return }
    do {
      try await repository.removeAllAssignments(for: ids)
      var updates: [String: [TagRecord]] = [:]
      for (path, tags) in assignmentCache.assignments {
        let filtered = tags.filter { !tagIDs.contains($0.id) }
        if filtered.count != tags.count {
          updates[path] = filtered
        }
      }
      assignmentCache.updateAssignments(updates)
      invalidateDirectoryCaches(forPaths: Array(updates.keys))
      await refreshAllTags()
      rebuildScopedTags()
      lastError = nil
    } catch {
      recordError(error)
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
      lastError = nil
    } catch {
      recordError(error)
    }
  }

  func remove(tagID: Int64, from url: URL) async {
    do {
      let tags = try await repository.remove(tagID: tagID, from: url)
      let path = url.standardizedFileURL.path
      assignmentCache.updateAssignments([path: tags])
      invalidateDirectoryCaches(forPaths: [path])
      await refreshAllTags()
      rebuildScopedTags()
      lastError = nil
    } catch {
      recordError(error)
    }
  }

  func deleteTag(_ tagID: Int64) async {
    do {
      try await repository.deleteTag(tagID)
      await refreshAllTags()
      var updates: [String: [TagRecord]] = [:]
      for (path, tags) in assignmentCache.assignments {
        let filtered = tags.filter { $0.id != tagID }
        if filtered.count != tags.count {
          updates[path] = filtered
        }
      }
      assignmentCache.updateAssignments(updates)
      invalidateDirectoryCaches(forPaths: Array(updates.keys))
      rebuildScopedTags()
      lastError = nil
    } catch {
      recordError(error)
    }
  }

  func deleteTags(_ tagIDs: Set<Int64>) async {
    guard !tagIDs.isEmpty else { return }
    do {
      try await repository.deleteTags(Array(tagIDs))
      await refreshAllTags()
      var updates: [String: [TagRecord]] = [:]
      for (path, tags) in assignmentCache.assignments {
        let filtered = tags.filter { !tagIDs.contains($0.id) }
        if filtered.count != tags.count {
          updates[path] = filtered
        }
      }
      assignmentCache.updateAssignments(updates)
      invalidateDirectoryCaches(forPaths: Array(updates.keys))
      rebuildScopedTags()
      lastError = nil
    } catch {
      recordError(error)
    }
  }

  func rename(tagID: Int64, to newName: String) async {
    let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
      recordError(message: L10n.string("tag_error_invalid_name"))
      return
    }
    do {
      try await repository.rename(tagID: tagID, newName: trimmed)
      await refreshAllTags()
      var updates: [String: [TagRecord]] = [:]
      for (path, tags) in assignmentCache.assignments {
        var mutated = tags
        var changed = false
        for index in mutated.indices where mutated[index].id == tagID {
          mutated[index] = TagRecord(
            id: mutated[index].id,
            name: trimmed,
            colorHex: mutated[index].colorHex,
            usageCount: mutated[index].usageCount,
            createdAt: mutated[index].createdAt,
            updatedAt: Date()
          )
          changed = true
        }
        if changed {
          updates[path] = mutated
        }
      }
      assignmentCache.updateAssignments(updates)
      rebuildScopedTags()
      lastError = nil
    } catch {
      recordError(error)
    }
  }

  func updateColor(tagID: Int64, hex: String?) async {
    await updateColor(tagIDs: [tagID], hex: hex)
  }

  func removeAssignments(for paths: [String]) {
    assignmentCache.remove(paths: paths)
    invalidateDirectoryCaches(forPaths: paths)
    rebuildScopedTags()
  }

  func clearFilter() {
    activeFilter = .init()
  }

  func clearTagFilters() {
    activeFilter.tagIDs = []
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
    guard let normalized = hex.normalizedHexColor() else { return }
    var sanitized = Set(activeFilter.colorHexes.compactMap { $0.normalizedHexColor() })
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
    smartFilterStore.promoteFilter(id: filter.id)
  }

  func saveCurrentFilterAsSmart(named name: String) throws {
    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return }
    guard activeFilter.isActive else { return }
    var sanitized = activeFilter
    sanitized.keyword = sanitized.keyword.trimmingCharacters(in: .whitespacesAndNewlines)
    sanitized.colorHexes = Set(sanitized.colorHexes.compactMap { $0.normalizedHexColor() })
    try smartFilterStore.save(filter: sanitized, named: trimmed)
  }

  func deleteSmartFilter(id: TagSmartFilter.ID) {
    smartFilterStore.delete(id: id)
  }

  func renameSmartFilter(id: TagSmartFilter.ID, to newName: String) throws {
    let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return }
    try smartFilterStore.rename(id: id, to: trimmed)
  }

  func reorderSmartFilters(from source: IndexSet, to destination: Int) {
    smartFilterStore.reorder(from: source, to: destination)
  }

  /// 根据当前激活的筛选器过滤图片路径集合，异步在后台计算
  func filteredImageURLs(from urls: [URL]) async -> [URL] {
    await filterManager.filteredImageURLs(
      filter: activeFilter,
      urls: urls,
      assignments: assignmentCache.assignments,
      assignmentsVersion: assignmentCache.version
    )
  }

  @MainActor
  func rebuildScopedTags() {
    assignmentCache.rebuildScopedTags()
    scopedTags = assignmentCache.scopedTags
    if scopedTags.isEmpty, activeFilter.isActive {
      activeFilter = .init()
      return
    }
    pruneFilter(availableIDs: Set(scopedTags.map(\.id)))
  }

  private func pruneFilter(availableIDs: Set<Int64>) {
    guard activeFilter.isActive else { return }
    let pruned = TagFilterManager.prunedFilter(activeFilter, availableIDs: availableIDs)
    if pruned != activeFilter {
      activeFilter = pruned
    }
  }

  private func reloadAssignmentsCache() async {
    let urls = assignmentCache.assignments.keys.map { URL(fileURLWithPath: $0) }
    guard !urls.isEmpty else { return }
    // 使用已有缓存的 Key 触发一次刷新，避免 UI 展示过期的标签颜色/名称
    await syncAssignments(for: urls)
  }

  func inspectNow(removeMissing: Bool = true) async {
    do {
      let summary = try await repository.inspectImages(removeMissing: removeMissing)
      lastInspection = summary
      if !summary.missingPaths.isEmpty {
        removeAssignments(for: summary.missingPaths)
      }
      recordSuccess(
        key: "tag_feedback_inspect_success",
        arguments: [
          summary.checkedCount,
          summary.recoveredCount,
          summary.removedCount
        ]
      )
    } catch {
      let message = String(
        format: L10n.string("tag_feedback_inspect_failure"),
        error.localizedDescription
      )
      recordError(message: message)
    }
  }

  func updateColor(tagIDs: Set<Int64>, hex: String?) async {
    guard !tagIDs.isEmpty else { return }
    do {
      try await repository.updateColor(tagIDs: Array(tagIDs), colorHex: hex)
      await refreshAllTags()
      updateCachedAssignmentsColor(tagIDs: tagIDs, hex: hex)
      rebuildScopedTags()
      lastError = nil
    } catch {
      recordError(error)
    }
  }

  /// 根据同目录文件与当前作用域热度计算推荐标签
  func recommendedTags(for url: URL, limit: Int = 8) async -> [TagRecord] {
    let directory = url.standardizedFileURL.deletingLastPathComponent().path
    let directoryStats = await directoryTagCounts(for: directory)
    return recommendationEngine.recommendedTags(
      for: url,
      assignments: assignments,
      scopedTags: scopedTags,
      allTags: allTags,
      directoryStats: directoryStats,
      limit: limit
    )
  }

  func recordRecommendationSelection(tagID: Int64, for url: URL) {
    let normalized = url.standardizedFileURL
    let context = TagRecommendationContext(
      imagePath: normalized.path,
      directory: normalized.deletingLastPathComponent().path,
      scopeSignature: scopedTags.hashValue
    )
    Task {
      await TagRecommendationTelemetry.shared.recordSelection(tagID: tagID, context: context)
    }
  }

  private func updateCachedAssignmentsColor(tagIDs: Set<Int64>, hex: String?) {
    guard !tagIDs.isEmpty else { return }
    var updates: [String: [TagRecord]] = [:]
    for (path, tags) in assignmentCache.assignments {
      var mutated = tags
      var changed = false
      for index in mutated.indices where tagIDs.contains(mutated[index].id) {
        mutated[index] = TagRecord(
          id: mutated[index].id,
          name: mutated[index].name,
          colorHex: hex,
          usageCount: mutated[index].usageCount,
          createdAt: mutated[index].createdAt,
          updatedAt: Date()
        )
        changed = true
      }
      if changed {
        updates[path] = mutated
      }
    }
    assignmentCache.updateAssignments(updates)
    invalidateDirectoryCaches(forPaths: Array(updates.keys))
  }

  private func recordSuccess(key: String, arguments: [CVarArg] = []) {
    lastError = nil
    let event = TagOperationFeedback(
      kind: .success,
      message: .localized(key: key, arguments: arguments)
    )
    feedbackEvent = event
    appendFeedbackHistory(event)
  }

  private func recordError(_ error: Error) {
    recordError(message: error.localizedDescription)
  }

  private func recordError(message: String) {
    lastError = message
    let event = TagOperationFeedback(
      kind: .failure,
      message: .literal(message)
    )
    feedbackEvent = event
    appendFeedbackHistory(event)
  }

  private func appendFeedbackHistory(_ event: TagOperationFeedback) {
    var history = feedbackHistory
    history.insert(event, at: 0)
    if history.count > 20 {
      history = Array(history.prefix(20))
    }
    feedbackHistory = history
  }

  private func directoryTagCounts(for directory: String) async -> [Int64: Int] {
    if let cached = await directoryStatsCache.cachedCounts(for: directory) {
      return cached
    }
    do {
      let fetched = try await repository.fetchDirectoryTagCounts(directory: directory)
      await directoryStatsCache.store(counts: fetched, for: directory)
      return fetched
    } catch {
      return [:]
    }
  }

  private func invalidateDirectoryCaches(forPaths paths: [String]) {
    let directories = Set(paths.map { path in
      URL(fileURLWithPath: path).deletingLastPathComponent().path
    })
    guard !directories.isEmpty else { return }
    Task {
      await directoryStatsCache.invalidate(directories: directories)
    }
  }
}
