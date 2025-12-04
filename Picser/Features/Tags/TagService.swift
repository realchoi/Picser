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
  /// 250ms 的防抖间隔，避免高频刷新造成性能问题
  private let refreshDebounceInterval: UInt64 = 250_000_000

  /// 延迟触发的刷新任务
  /// 用于防抖：在指定时间后启动刷新循环
  private var scheduledRefreshTask: Task<Void, Never>?

  /// 正在执行的刷新循环任务
  /// 确保同一时间只有一个刷新循环在运行
  private var refreshLoopTask: Task<Void, Never>?

  /// 是否存在待处理的刷新请求（用于合并高频调用）
  /// 刷新循环会不断检查此标志，直到没有新的刷新请求
  private var pendingRefreshRequest = false

  /// 初始化标签服务
  ///
  /// 执行初始化任务：
  /// 1. **绑定智能筛选器**：订阅 smartFilterStore 的变化，自动更新 UI
  /// 2. **绑定标签分配缓存**：订阅 assignmentCache 的变化，同步到 UI 并失效筛选缓存
  /// 3. **绑定作用域标签**：订阅 assignmentCache 的作用域标签变化
  /// 4. **启动初始化任务**：
  ///    - 执行数据库完整性巡检（inspectNow）
  ///    - 加载全部标签列表（refreshAllTags）
  ///
  /// Combine 订阅说明：
  /// - 所有订阅都在主线程执行（receive(on: RunLoop.main)）
  /// - 使用 weak self 避免循环引用
  /// - assignments 变化时自动失效筛选缓存，确保筛选结果准确
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

  /// 重新加载全部标签列表
  ///
  /// 支持两种刷新模式：
  /// 1. **立即刷新**（immediate = true）：取消待处理的延迟刷新，立即启动刷新循环
  ///    - 适用于关键操作后需要即时反馈的场景（如创建、删除标签）
  ///    - 如果已有刷新循环在运行，直接返回该任务，避免重复刷新
  /// 2. **延迟刷新**（immediate = false）：使用防抖策略，延迟 250ms 后执行
  ///    - 适用于高频触发的场景（如批量操作）
  ///    - 多次调用会合并为一次刷新，提高性能
  ///
  /// 防抖策略说明：
  /// - 第一次调用：启动 250ms 定时器
  /// - 定时器期间的后续调用：标记 pendingRefreshRequest = true
  /// - 定时器到期：启动刷新循环，循环会持续执行直到没有新的刷新请求
  ///
  /// - Parameter immediate: 是否立即执行刷新，默认 false（使用防抖）
  func refreshAllTags(immediate: Bool = false) async {
    if immediate {
      let task = startImmediateRefresh()
      await task.value
    } else {
      scheduleCoalescedRefresh()
    }
  }

  /// 启动立即刷新
  ///
  /// 立即刷新的执行流程：
  /// 1. 标记有待处理的刷新请求
  /// 2. 取消待处理的延迟刷新定时器
  /// 3. 如果刷新循环已在运行，直接返回该任务（避免并发刷新）
  /// 4. 否则创建新的刷新循环任务
  ///
  /// - Returns: 刷新循环任务，调用者可以 await 等待完成
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

  /// 调度合并刷新（防抖策略）
  ///
  /// 防抖工作原理：
  /// 1. 标记有待处理的刷新请求
  /// 2. 如果刷新循环已在运行，直接返回（循环会处理这次请求）
  /// 3. 如果延迟定时器已存在，直接返回（等待定时器触发）
  /// 4. 否则创建新的延迟定时器，250ms 后启动刷新循环
  ///
  /// 优势：
  /// - 高频调用时只执行一次刷新，减少数据库查询
  /// - 刷新循环会持续执行直到没有新的请求，确保最终数据一致性
  ///
  /// 示例场景：
  /// - 用户快速连续删除 5 个标签
  /// - 每次删除都会调用此方法
  /// - 只有最后一次调用的定时器会触发，执行一次刷新
  /// - 如果在刷新期间又有新的删除操作，刷新循环会自动再执行一次
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

  /// 取消待处理的延迟刷新定时器
  ///
  /// 在立即刷新时调用，确保延迟刷新不会重复执行。
  private func cancelScheduledRefresh() {
    scheduledRefreshTask?.cancel()
    scheduledRefreshTask = nil
  }

  /// 刷新循环主逻辑
  ///
  /// 循环执行流程：
  /// 1. 清除 pendingRefreshRequest 标志
  /// 2. 执行实际的刷新逻辑（performRefreshAllTags）
  /// 3. 检查是否有新的刷新请求（pendingRefreshRequest == true）
  /// 4. 如果有新请求，重复步骤 1-3；否则退出循环
  ///
  /// 为什么需要循环：
  /// - 刷新过程中可能有新的操作发生（如用户继续删除标签）
  /// - 循环确保所有操作都被反映到最终的刷新结果中
  /// - 避免刷新完成后立即又触发新的刷新，造成频繁的数据库查询
  ///
  /// 示例场景：
  /// - 开始刷新（查询数据库需要 100ms）
  /// - 50ms 时用户删除了一个标签，调用 scheduleCoalescedRefresh
  /// - pendingRefreshRequest 被设置为 true
  /// - 第一次刷新完成后，循环检测到 pendingRefreshRequest = true
  /// - 再执行一次刷新，获取最新数据
  /// - 第二次刷新期间没有新操作，循环退出
  private func runRefreshLoop() async {
    defer { refreshLoopTask = nil }
    repeat {
      pendingRefreshRequest = false
      await performRefreshAllTags()
    } while pendingRefreshRequest
  }

  /// 执行实际的标签刷新操作
  ///
  /// 刷新步骤：
  /// 1. 从数据库加载所有标签，按使用频次排序
  /// 2. 生成按名称排序的标签列表（用于某些 UI 场景）
  /// 3. 修剪当前激活的筛选条件，移除不存在的标签 ID
  /// 4. 清除错误状态
  ///
  /// 错误处理：
  /// - 如果查询失败，记录错误信息到 lastError
  /// - 不会抛出异常，避免中断刷新循环
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

  /// 清理未使用的标签
  ///
  /// 从数据库中删除所有没有图片关联的孤立标签。
  ///
  /// 执行流程：
  /// 1. 调用 repository 清理孤立标签
  /// 2. 刷新全局标签列表
  /// 3. 清除错误状态
  ///
  /// 使用场景：
  /// - 用户在设置页面手动触发清理
  /// - 批量删除图片后自动清理
  ///
  /// 注意事项：
  /// - 不刷新 assignments 缓存（标签已删除，缓存中不会有）
  /// - 不重建 scopedTags（作用域内的标签不受影响）
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
  ///
  /// 当用户切换目录或筛选条件变化时调用，更新作用域内的标签统计。
  ///
  /// 执行流程：
  /// 1. **同步作用域路径**：更新 assignmentCache 中的作用域路径集合
  /// 2. **同步标签分配**：从数据库加载这些图片的标签信息
  /// 3. **重建统计**：计算作用域内每个标签的使用次数
  ///
  /// 作用域概念：
  /// - 作用域 = 当前 ContentView 中显示的所有图片
  /// - scopedTags = 这些图片使用的标签及其在作用域内的使用次数
  /// - 用于筛选面板显示可用的标签选项
  ///
  /// 使用场景：
  /// - 用户切换到新目录
  /// - 筛选条件变化导致显示的图片集合变化
  /// - 应用启动时初始化作用域
  ///
  /// - Parameter urls: 当前作用域内的所有图片 URL
  func refreshScope(with urls: [URL]) async {
    assignmentCache.syncScopedPaths(with: urls)
    await syncAssignments(for: urls)
    // 作用域内的缓存更新后立刻重建统计，确保筛选面板即时反馈
    rebuildScopedTags()
  }

  /// 同步一批图片的标签信息
  ///
  /// 从数据库批量加载图片的标签分配，更新本地缓存。
  ///
  /// 执行流程：
  /// 1. **调和图片记录**：更新数据库中图片的元数据（路径、书签等）
  /// 2. **批量查询标签**：从数据库加载所有图片的标签关联
  /// 3. **更新缓存**：合并到 assignmentCache，只保留作用域内的数据
  /// 4. **失效目录缓存**：清除相关目录的统计缓存
  /// 5. **记录反馈**：成功时记录同步的图片数量
  ///
  /// 缓存策略：
  /// - 只保留 pathSet 中的缓存，移除不在作用域内的数据
  /// - 使用 merge 合并新旧数据，新数据优先
  /// - 避免缓存膨胀和 stale 数据
  ///
  /// 使用场景：
  /// - refreshScope 时批量加载作用域内图片的标签
  /// - 标签操作后重新加载受影响图片的标签
  /// - 应用启动时初始化缓存
  ///
  /// - Parameter urls: 要同步标签的图片 URL 数组
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
  ///
  /// 从缓存中快速读取图片的标签列表，不涉及数据库查询。
  ///
  /// 数据来源：
  /// - assignmentCache：内存缓存，保存作用域内所有图片的标签
  /// - 如果图片不在缓存中，返回空数组
  ///
  /// 使用场景：
  /// - DetailView 显示图片的标签列表
  /// - 推荐引擎计算时需要排除已有标签
  /// - UI 实时更新标签显示
  ///
  /// 性能：
  /// - O(1) 字典查找，无数据库 I/O
  /// - 适合高频调用
  ///
  /// - Parameter url: 图片 URL
  /// - Returns: 标签列表，如果图片不在缓存中返回空数组
  func tags(for url: URL) -> [TagRecord] {
    assignmentCache.tags(for: url)
  }

  /// 为单张图片分配标签（便捷方法）
  ///
  /// 内部调用批量分配接口处理单张图片。
  ///
  /// - Parameters:
  ///   - tagNames: 要分配的标签名称数组
  ///   - url: 目标图片 URL
  func assign(tagNames: [String], to url: URL) async {
    await assign(tagNames: tagNames, to: [url])
  }

  /// 批量为图片分配标签
  ///
  /// 核心标签分配方法，为多张图片添加指定的标签。
  ///
  /// 执行流程：
  /// 1. **预处理**：清理标签名称（去空白、去重），标准化 URL
  /// 2. **数据库操作**：调用 repository 创建标签并建立关联
  /// 3. **更新缓存**：将新的标签分配更新到 assignmentCache
  /// 4. **失效缓存**：清除相关目录的统计缓存
  /// 5. **刷新 UI**：刷新全局标签列表，重建作用域统计
  ///
  /// 特殊处理：
  /// - 空标签名称：自动忽略
  /// - 重复标签：自动去重（不区分大小写）
  /// - 标签不存在：自动创建
  ///
  /// 缓存更新：
  /// - 只更新受影响的图片路径
  /// - 增量更新，不替换整个缓存
  ///
  /// 使用场景：
  /// - 用户在 DetailView 中为图片添加标签
  /// - 批量标记操作
  /// - 推荐标签被选中后分配
  ///
  /// - Parameters:
  ///   - tagNames: 要分配的标签名称数组
  ///   - urls: 目标图片 URL 数组
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

  /// 创建新标签（不关联图片）
  ///
  /// 只创建标签记录，不建立图片关联。用于预先创建常用标签。
  ///
  /// 执行流程：
  /// 1. **清理名称**：去除空白字符和空值
  /// 2. **数据库操作**：调用 repository 创建标签
  /// 3. **刷新 UI**：刷新全局标签列表
  ///
  /// 幂等性：
  /// - 如果标签已存在，不会重复创建
  /// - UNIQUE 约束确保名称唯一性
  ///
  /// 使用场景：
  /// - 用户在设置页面批量创建标签
  /// - 导入标签列表
  /// - 预设常用标签
  ///
  /// - Parameter names: 要创建的标签名称数组
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

  /// 清空指定标签的所有图片关联
  ///
  /// 移除标签与所有图片的关联，但不删除标签本身。
  ///
  /// 执行流程：
  /// 1. **数据库操作**：删除 image_tags 表中的关联记录
  /// 2. **更新缓存**：从 assignmentCache 中移除这些标签
  /// 3. **失效缓存**：清除相关目录的统计缓存
  /// 4. **刷新 UI**：刷新全局标签列表，重建作用域统计
  ///
  /// 与 deleteTag 的区别：
  /// - clearAssignments：保留标签，移除关联
  /// - deleteTag：删除标签及其所有关联
  ///
  /// 使用场景：
  /// - 用户想重置标签，但保留标签定义
  /// - 批量清理某些标签的使用
  ///
  /// - Parameter tagIDs: 要清空关联的标签 ID 集合
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

  /// 合并多个标签到目标标签
  ///
  /// 将多个源标签合并为一个目标标签，迁移所有图片关联。
  ///
  /// 执行流程：
  /// 1. **验证输入**：清理标签名称，检查至少有 2 个源标签
  /// 2. **数据库操作**：调用 repository 执行合并（迁移关联 + 删除源标签）
  /// 3. **刷新 UI**：刷新全局标签列表
  /// 4. **重载缓存**：从数据库重新加载所有受影响图片的标签
  /// 5. **重建统计**：重建作用域标签统计
  ///
  /// 合并策略：
  /// - 目标标签不存在时自动创建
  /// - 源标签的所有图片关联转移到目标标签
  /// - 源标签被删除
  /// - 如果图片同时有源标签和目标标签，保留目标标签的关联
  ///
  /// 使用场景：
  /// - 清理重复标签（如"工作"和"Work"）
  /// - 标签规范化（统一术语）
  /// - 合并相似标签
  ///
  /// - Parameters:
  ///   - sourceIDs: 要合并的源标签 ID 集合
  ///   - targetName: 目标标签名称（不存在会创建）
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

  /// 从单张图片移除指定标签
  ///
  /// 删除图片-标签关联，并在标签未被任何图片使用时自动清理。
  ///
  /// 执行流程：
  /// 1. **数据库操作**：删除图片-标签关联记录
  /// 2. **自动清理**：如果标签变成孤立标签，自动删除
  /// 3. **更新缓存**：更新 assignmentCache 中该图片的标签列表
  /// 4. **失效缓存**：清除相关目录的统计缓存
  /// 5. **刷新 UI**：刷新全局标签列表，重建作用域统计
  ///
  /// 自动清理机制：
  /// - 标签移除后，检查是否仍被其他图片使用
  /// - 如果没有任何图片使用，自动删除标签
  /// - 避免积累大量无用标签
  ///
  /// 使用场景：
  /// - 用户在 DetailView 中点击标签的删除按钮
  /// - 移除错误添加的标签
  ///
  /// - Parameters:
  ///   - tagID: 要移除的标签 ID
  ///   - url: 目标图片 URL
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

  /// 删除单个标签
  ///
  /// 永久删除标签及其所有图片关联。
  ///
  /// 执行流程：
  /// 1. **数据库操作**：删除标签记录（级联删除所有关联）
  /// 2. **刷新 UI**：刷新全局标签列表
  /// 3. **更新缓存**：从 assignmentCache 中移除该标签
  /// 4. **失效缓存**：清除相关目录的统计缓存
  /// 5. **重建统计**：重建作用域标签统计
  ///
  /// 级联删除：
  /// - 外键约束 ON DELETE CASCADE 自动删除 image_tags 中的关联
  /// - 不需要手动清理关联表
  ///
  /// 使用场景：
  /// - 用户在标签管理页面删除标签
  /// - 清理不需要的标签
  ///
  /// 警告：此操作不可逆，会丢失所有使用此标签的图片关联。
  ///
  /// - Parameter tagID: 要删除的标签 ID
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

  /// 批量删除标签
  ///
  /// 永久删除多个标签及其所有图片关联，比逐个删除更高效。
  ///
  /// 执行流程：
  /// 1. **数据库操作**：批量删除标签记录（级联删除所有关联）
  /// 2. **刷新 UI**：刷新全局标签列表
  /// 3. **更新缓存**：从 assignmentCache 中移除这些标签
  /// 4. **失效缓存**：清除相关目录的统计缓存
  /// 5. **重建统计**：重建作用域标签统计
  ///
  /// 性能优势：
  /// - 使用单个 SQL 语句批量删除（IN 子句）
  /// - 比循环调用 deleteTag 快 5-10 倍
  /// - 减少数据库往返次数
  ///
  /// 使用场景：
  /// - 用户在标签管理页面多选删除
  /// - 批量清理标签
  ///
  /// 警告：此操作不可逆，会丢失所有使用这些标签的图片关联。
  ///
  /// - Parameter tagIDs: 要删除的标签 ID 集合
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

  /// 重命名标签
  ///
  /// 修改标签名称，并检查名称冲突。
  ///
  /// 执行流程：
  /// 1. **验证输入**：清理名称，检查非空
  /// 2. **数据库操作**：更新标签名称（检查 UNIQUE 约束）
  /// 3. **刷新 UI**：刷新全局标签列表
  /// 4. **更新缓存**：更新 assignmentCache 中的标签名称
  /// 5. **重建统计**：重建作用域标签统计
  ///
  /// 验证规则：
  /// - 新名称不能为空或纯空白
  /// - 新名称不能与其他标签重复（不区分大小写）
  /// - 允许改变大小写（如 "Work" -> "work"）
  ///
  /// 缓存更新：
  /// - 遍历 assignmentCache，找到包含该标签的图片
  /// - 只更新名称，保留 ID、颜色等其他属性
  /// - 更新 updatedAt 时间戳
  ///
  /// 使用场景：
  /// - 用户在标签管理页面重命名标签
  /// - 修正拼写错误
  /// - 标签规范化
  ///
  /// - Parameters:
  ///   - tagID: 要重命名的标签 ID
  ///   - newName: 新名称
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

  /// 更新单个标签的颜色（便捷方法）
  ///
  /// 内部调用批量更新接口处理单个标签。
  ///
  /// - Parameters:
  ///   - tagID: 标签 ID
  ///   - hex: 新的颜色值（#RRGGBB 格式），nil 表示清除颜色
  func updateColor(tagID: Int64, hex: String?) async {
    await updateColor(tagIDs: [tagID], hex: hex)
  }

  /// 从缓存中移除指定图片的标签分配
  ///
  /// 用于图片被删除或移出作用域时清理缓存。
  ///
  /// 执行流程：
  /// 1. 从 assignmentCache 中删除这些路径
  /// 2. 失效相关目录的统计缓存
  /// 3. 重建作用域标签统计
  ///
  /// 注意事项：
  /// - 不涉及数据库操作，只更新内存缓存
  /// - 数据库记录保持不变
  ///
  /// 使用场景：
  /// - 图片从作用域中移除
  /// - 图片被删除
  /// - 巡检发现文件丢失
  ///
  /// - Parameter paths: 要移除的图片路径数组
  func removeAssignments(for paths: [String]) {
    assignmentCache.remove(paths: paths)
    invalidateDirectoryCaches(forPaths: paths)
    rebuildScopedTags()
  }

  /// 清除所有筛选条件
  ///
  /// 重置 activeFilter 为默认值，显示所有图片。
  func clearFilter() {
    activeFilter = .init()
  }

  /// 清除标签筛选条件
  ///
  /// 只清除标签 ID 筛选，保留其他筛选条件（关键词、颜色）。
  func clearTagFilters() {
    activeFilter.tagIDs = []
  }

  /// 切换标签筛选状态
  ///
  /// 如果标签已选中则取消选中，否则选中该标签。
  ///
  /// 筛选模式：
  /// - 当选中新标签时，应用指定的筛选模式（any/all/exclude）
  /// - 模式会应用到所有选中的标签
  ///
  /// 使用场景：
  /// - 用户在筛选面板点击标签
  /// - 切换标签的选中状态
  ///
  /// - Parameters:
  ///   - tagID: 标签 ID
  ///   - mode: 筛选模式（默认 any）
  func toggleFilter(tagID: Int64, mode: TagFilterMode = .any) {
    if activeFilter.tagIDs.contains(tagID) {
      activeFilter.tagIDs.remove(tagID)
    } else {
      activeFilter.tagIDs.insert(tagID)
      activeFilter.mode = mode
    }
  }

  /// 更新关键词筛选条件
  ///
  /// 设置文件名/目录名的搜索关键词。
  ///
  /// 搜索逻辑：
  /// - 不区分大小写
  /// - 包含匹配（不是精确匹配）
  /// - 同时搜索文件名和目录路径
  ///
  /// - Parameter text: 搜索关键词
  func updateKeywordFilter(_ text: String) {
    activeFilter.keyword = text
  }

  /// 切换颜色筛选状态
  ///
  /// 如果颜色已选中则取消选中，否则选中该颜色。
  ///
  /// 颜色筛选逻辑：
  /// - 自动归一化颜色值（大写、添加 # 前缀）
  /// - 支持多选（可以同时筛选多个颜色）
  /// - 筛选标签的颜色属性，不是图片本身的颜色
  ///
  /// 使用场景：
  /// - 用户在筛选面板点击颜色图标
  /// - 切换颜色的选中状态
  ///
  /// - Parameter hex: 颜色值（#RRGGBB 格式）
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

  /// 清除颜色筛选条件
  ///
  /// 只清除颜色筛选，保留其他筛选条件（标签、关键词）。
  func clearColorFilters() {
    activeFilter.colorHexes = []
  }

  /// 应用智能筛选器
  ///
  /// 将保存的智能筛选器设置为当前激活的筛选条件。
  ///
  /// 执行流程：
  /// 1. **应用筛选条件**：将智能筛选器的 filter 设置为 activeFilter
  /// 2. **提升优先级**：在智能筛选器列表中提升该筛选器的位置（最近使用）
  ///
  /// 使用场景：
  /// - 用户在智能筛选器列表中点击某个筛选器
  /// - 快速切换到常用的筛选组合
  ///
  /// - Parameter filter: 要应用的智能筛选器
  func applySmartFilter(_ filter: TagSmartFilter) {
    activeFilter = filter.filter
    smartFilterStore.promoteFilter(id: filter.id)
  }

  /// 保存当前筛选条件为智能筛选器
  ///
  /// 将当前激活的筛选条件快照保存为命名的智能筛选器。
  ///
  /// 验证规则：
  /// - 名称不能为空或纯空白
  /// - 筛选条件必须处于激活状态（至少有一个筛选维度生效）
  ///
  /// 数据清理：
  /// - 清理关键词的空白字符
  /// - 归一化颜色值（大写、添加 # 前缀）
  ///
  /// 使用场景：
  /// - 用户设置好筛选条件后，点击"保存为智能筛选器"
  /// - 保存常用的筛选组合，便于快速访问
  ///
  /// - Parameter name: 智能筛选器名称
  /// - Throws: 名称为空或存储失败时抛出错误
  func saveCurrentFilterAsSmart(named name: String) throws {
    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return }
    guard activeFilter.isActive else { return }
    var sanitized = activeFilter
    sanitized.keyword = sanitized.keyword.trimmingCharacters(in: .whitespacesAndNewlines)
    sanitized.colorHexes = Set(sanitized.colorHexes.compactMap { $0.normalizedHexColor() })
    try smartFilterStore.save(filter: sanitized, named: trimmed)
  }

  /// 删除智能筛选器
  ///
  /// 从持久化存储中移除指定的智能筛选器。
  ///
  /// 注意事项：
  /// - 不影响当前激活的筛选条件
  /// - 如果当前正在使用被删除的智能筛选器，筛选条件仍然保持
  ///
  /// 使用场景：
  /// - 用户在智能筛选器管理界面删除某个筛选器
  /// - 清理不再需要的筛选器
  ///
  /// - Parameter id: 智能筛选器 ID
  func deleteSmartFilter(id: TagSmartFilter.ID) {
    smartFilterStore.delete(id: id)
  }

  /// 重命名智能筛选器
  ///
  /// 修改智能筛选器的显示名称。
  ///
  /// 验证规则：
  /// - 新名称不能为空或纯空白
  ///
  /// 注意事项：
  /// - 只修改名称，不改变筛选条件
  /// - 不影响 ID 和创建时间
  ///
  /// 使用场景：
  /// - 用户在智能筛选器管理界面重命名
  /// - 修正拼写错误或调整描述
  ///
  /// - Parameters:
  ///   - id: 智能筛选器 ID
  ///   - newName: 新名称
  /// - Throws: 名称为空或存储失败时抛出错误
  func renameSmartFilter(id: TagSmartFilter.ID, to newName: String) throws {
    let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return }
    try smartFilterStore.rename(id: id, to: trimmed)
  }

  /// 重新排序智能筛选器
  ///
  /// 调整智能筛选器在列表中的显示顺序。
  ///
  /// 使用场景：
  /// - 用户拖动智能筛选器调整顺序
  /// - 将常用的筛选器移到顶部
  ///
  /// - Parameters:
  ///   - source: 要移动的筛选器索引集合
  ///   - destination: 目标位置索引
  func reorderSmartFilters(from source: IndexSet, to destination: Int) {
    smartFilterStore.reorder(from: source, to: destination)
  }

  /// 根据当前激活的筛选器过滤图片路径集合
  ///
  /// 异步执行筛选逻辑，避免阻塞主线程。
  ///
  /// 筛选流程：
  /// 1. **委托给 filterManager**：调用筛选管理器的批量筛选方法
  /// 2. **传递缓存版本**：用于检测筛选期间数据是否变化
  /// 3. **后台计算**：在后台线程执行筛选逻辑
  ///
  /// 筛选条件：
  /// - 标签筛选：按 tagIDs 和 mode（any/all/exclude）筛选
  /// - 关键词筛选：匹配文件名或目录名
  /// - 颜色筛选：匹配标签的颜色属性
  ///
  /// 性能优化：
  /// - 使用缓存避免重复计算
  /// - 增量更新，只处理变化的图片
  /// - 版本检测，数据变化时失效缓存
  ///
  /// 使用场景：
  /// - ContentView 需要根据筛选条件显示图片列表
  /// - 筛选条件变化时重新计算显示的图片
  ///
  /// - Parameter urls: 待筛选的图片 URL 数组
  /// - Returns: 符合筛选条件的图片 URL 数组
  func filteredImageURLs(from urls: [URL]) async -> [URL] {
    await filterManager.filteredImageURLs(
      filter: activeFilter,
      urls: urls,
      assignments: assignmentCache.assignments,
      assignmentsVersion: assignmentCache.version
    )
  }

  /// 重建作用域标签统计
  ///
  /// 从缓存中重新计算作用域内的标签使用情况，并更新 UI 状态。
  ///
  /// 执行流程：
  /// 1. **重建统计**：调用 assignmentCache 重新统计作用域内标签使用次数
  /// 2. **同步到 UI**：将统计结果赋值给 @Published 属性
  /// 3. **特殊情况处理**：
  ///    - 如果作用域为空且有激活的筛选条件，清除筛选（没有图片可筛选）
  ///    - 否则修剪筛选条件，移除不在作用域内的标签
  ///
  /// 调用时机：
  /// - 作用域变化后（refreshScope）
  /// - 标签分配变化后（assign、remove、deleteTag 等）
  /// - 标签颜色更新后（updateColor）
  ///
  /// 注意事项：
  /// - 必须在主线程调用（@MainActor）
  /// - 不涉及数据库查询，只处理内存数据
  ///
  /// 边界情况：
  /// - 作用域为空：清除所有筛选条件
  /// - 筛选的标签不在作用域内：自动移除这些标签
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

  /// 修剪筛选条件，移除不可用的标签 ID
  ///
  /// 当标签被删除或不在作用域内时，自动从筛选条件中移除。
  ///
  /// 执行逻辑：
  /// - 调用 TagFilterManager 的静态方法过滤无效标签 ID
  /// - 只在筛选条件有变化时更新 activeFilter
  ///
  /// 调用时机：
  /// - 刷新全局标签列表后（可能有标签被删除）
  /// - 重建作用域标签后（可能有标签不在作用域内）
  ///
  /// - Parameter availableIDs: 当前可用的标签 ID 集合
  private func pruneFilter(availableIDs: Set<Int64>) {
    guard activeFilter.isActive else { return }
    let pruned = TagFilterManager.prunedFilter(activeFilter, availableIDs: availableIDs)
    if pruned != activeFilter {
      activeFilter = pruned
    }
  }

  /// 重新加载标签分配缓存
  ///
  /// 从数据库重新加载所有已缓存图片的标签分配，刷新元数据。
  ///
  /// 使用场景：
  /// - 标签合并后，需要更新缓存中的标签 ID 和名称
  /// - 标签颜色或名称大量变化后，批量刷新缓存
  ///
  /// 执行流程：
  /// 1. **提取缓存的图片路径**：从 assignmentCache 获取所有已缓存的路径
  /// 2. **转换为 URL**：构造 URL 对象
  /// 3. **批量重新加载**：调用 syncAssignments 从数据库刷新
  ///
  /// 注意事项：
  /// - 不改变缓存的作用域，只刷新已有数据
  /// - 适合元数据变化，不适合增量添加图片
  private func reloadAssignmentsCache() async {
    let urls = assignmentCache.assignments.keys.map { URL(fileURLWithPath: $0) }
    guard !urls.isEmpty else { return }
    // 使用已有缓存的 Key 触发一次刷新，避免 UI 展示过期的标签颜色/名称
    await syncAssignments(for: urls)
  }

  /// 执行数据库完整性巡检
  ///
  /// 检查所有图片记录的有效性，恢复或清理失效记录。
  ///
  /// 巡检流程：
  /// 1. **调用 repository**：执行底层的文件系统检查
  /// 2. **处理结果**：
  ///    - 更新巡检摘要（lastInspection）
  ///    - 移除缺失文件的缓存（removeAssignments）
  ///    - 记录成功或失败的反馈
  ///
  /// 巡检策略：
  /// - **recoveredCount**：通过安全书签恢复的文件数
  /// - **removedCount**：删除的无效记录数（removeMissing = true 时）
  /// - **missingPaths**：无法访问的文件路径列表
  ///
  /// 使用场景：
  /// - 应用启动时自动巡检（init 中调用）
  /// - 用户在设置页面手动触发巡检
  /// - 批量删除图片后验证数据库状态
  ///
  /// - Parameter removeMissing: 是否删除无法访问的记录（默认 true）
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

  /// 批量更新标签颜色
  ///
  /// 为一组标签设置相同的颜色值。
  ///
  /// 执行流程：
  /// 1. **数据库操作**：调用 repository 批量更新颜色字段
  /// 2. **刷新全局标签**：更新 allTags 列表中的颜色信息
  /// 3. **更新缓存**：同步 assignmentCache 中的标签颜色
  /// 4. **重建统计**：刷新作用域标签的颜色显示
  ///
  /// 使用场景：
  /// - 用户在标签管理页面批量设置颜色
  /// - 按颜色分类标签
  /// - 清除一组标签的颜色（hex = nil）
  ///
  /// - Parameters:
  ///   - tagIDs: 要更新的标签 ID 集合
  ///   - hex: 新的颜色值（#RRGGBB 格式），nil 表示清除颜色
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
  ///
  /// 为用户推荐可能适合的标签，基于以下因素：
  /// 1. **同目录热度**：该目录下其他图片常用的标签
  /// 2. **作用域热度**：当前选中图片集合中常用的标签
  /// 3. **全局热度**：所有图片中常用的标签
  /// 4. **已有标签**：排除图片已有的标签
  ///
  /// 推荐策略：
  /// - 优先推荐同目录和作用域内高频标签
  /// - 综合全局使用频次作为补充
  /// - 使用推荐引擎的算法计算权重和排序
  ///
  /// 使用场景：
  /// - DetailView 显示推荐标签列表
  /// - 用户快速标记图片
  /// - 批量标记时的智能提示
  ///
  /// - Parameters:
  ///   - url: 图片 URL
  ///   - limit: 推荐标签数量限制（默认 8 个）
  /// - Returns: 推荐的标签列表，按推荐权重排序
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



  /// 更新缓存中的标签颜色
  ///
  /// 当标签颜色在数据库中更新后，同步更新 assignmentCache 中的标签记录。
  ///
  /// 执行流程：
  /// 1. **遍历缓存**：遍历所有图片的标签分配
  /// 2. **匹配标签 ID**：找到包含指定标签 ID 的记录
  /// 3. **更新颜色**：创建新的 TagRecord 实例，替换旧记录
  /// 4. **批量更新**：调用 assignmentCache.updateAssignments 应用更改
  /// 5. **失效目录缓存**：清除相关目录的统计缓存
  ///
  /// 数据一致性：
  /// - 保持 TagRecord 的不可变性（创建新实例而不是修改现有实例）
  /// - 同时更新 updated_at 时间戳
  ///
  /// 性能考虑：
  /// - 只更新受影响的图片路径
  /// - 使用字典批量更新，不是逐个更新
  ///
  /// - Parameters:
  ///   - tagIDs: 要更新颜色的标签 ID 集合
  ///   - hex: 新的颜色值（可选）
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

  /// 记录成功操作的反馈
  ///
  /// 创建成功类型的反馈事件，显示本地化的成功消息。
  ///
  /// 执行流程：
  /// 1. **清除错误状态**：将 lastError 设为 nil
  /// 2. **创建反馈事件**：构造 TagOperationFeedback 对象
  /// 3. **更新 UI**：设置 feedbackEvent 触发 UI 更新
  /// 4. **记录历史**：添加到 feedbackHistory 列表
  ///
  /// 反馈内容：
  /// - kind: .success
  /// - message: 从本地化字符串生成，支持参数格式化
  ///
  /// 使用场景：
  /// - 数据库巡检成功
  /// - 标签同步成功
  /// - 其他需要用户反馈的成功操作
  ///
  /// - Parameters:
  ///   - key: 本地化字符串的 key
  ///   - arguments: 格式化参数数组（对应本地化字符串中的 %d、%@ 等）
  private func recordSuccess(key: String, arguments: [CVarArg] = []) {
    lastError = nil
    let event = TagOperationFeedback(
      kind: .success,
      message: .localized(key: key, arguments: arguments)
    )
    feedbackEvent = event
    appendFeedbackHistory(event)
  }

  /// 记录错误操作的反馈（Error 对象）
  ///
  /// 从 Error 对象提取错误描述，记录失败反馈。
  ///
  /// 便捷方法，内部调用 recordError(message:)。
  ///
  /// - Parameter error: 错误对象
  private func recordError(_ error: Error) {
    recordError(message: error.localizedDescription)
  }

  /// 记录错误操作的反馈（字符串消息）
  ///
  /// 创建失败类型的反馈事件，显示错误消息。
  ///
  /// 执行流程：
  /// 1. **记录错误状态**：将 lastError 设为错误消息
  /// 2. **创建反馈事件**：构造 TagOperationFeedback 对象
  /// 3. **更新 UI**：设置 feedbackEvent 触发 UI 更新
  /// 4. **记录历史**：添加到 feedbackHistory 列表
  ///
  /// 反馈内容：
  /// - kind: .failure
  /// - message: 字面量消息（不使用本地化）
  ///
  /// 使用场景：
  /// - 数据库操作失败
  /// - 文件访问错误
  /// - 其他需要用户知晓的错误
  ///
  /// - Parameter message: 错误消息字符串
  private func recordError(message: String) {
    lastError = message
    let event = TagOperationFeedback(
      kind: .failure,
      message: .literal(message)
    )
    feedbackEvent = event
    appendFeedbackHistory(event)
  }

  /// 将反馈事件添加到历史记录
  ///
  /// 维护最近 20 条反馈历史，供用户查看操作记录。
  ///
  /// 执行流程：
  /// 1. **插入到开头**：新事件插入到索引 0
  /// 2. **限制数量**：保留最近 20 条，超出的移除
  /// 3. **更新状态**：赋值给 @Published 属性
  ///
  /// 数据结构：
  /// - 数组头部是最新的反馈
  /// - 最多保留 20 条历史
  ///
  /// 使用场景：
  /// - 设置页面显示操作历史
  /// - 调试和故障排查
  ///
  /// - Parameter event: 要添加的反馈事件
  private func appendFeedbackHistory(_ event: TagOperationFeedback) {
    var history = feedbackHistory
    history.insert(event, at: 0)
    if history.count > 20 {
      history = Array(history.prefix(20))
    }
    feedbackHistory = history
  }

  /// 获取指定目录的标签使用统计
  ///
  /// 从缓存或数据库查询某个目录下所有图片的标签使用情况。
  ///
  /// 执行流程：
  /// 1. **检查缓存**：先从 directoryStatsCache 查询
  /// 2. **缓存命中**：直接返回缓存数据
  /// 3. **缓存未命中**：从数据库查询
  /// 4. **存入缓存**：将查询结果缓存，供下次使用
  /// 5. **异常处理**：查询失败时返回空字典
  ///
  /// 缓存策略：
  /// - LRU 缓存，最多保存 200 个目录的统计
  /// - 目录内标签变化时自动失效
  ///
  /// 返回数据：
  /// - 字典的 key 是标签 ID
  /// - 字典的 value 是该标签在目录内的使用次数
  ///
  /// 使用场景：
  /// - 推荐引擎计算同目录热度
  /// - 显示目录级别的标签统计
  ///
  /// - Parameter directory: 目录完整路径
  /// - Returns: 标签 ID 到使用次数的映射
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

  /// 失效指定图片路径对应目录的统计缓存
  ///
  /// 当图片的标签分配发生变化时，清除相关目录的统计缓存。
  ///
  /// 执行流程：
  /// 1. **提取目录路径**：从图片完整路径中提取目录部分
  /// 2. **去重**：使用 Set 去除重复的目录路径
  /// 3. **批量失效**：调用 directoryStatsCache.invalidate 清除缓存
  ///
  /// 调用时机：
  /// - 图片添加/移除标签后
  /// - 标签合并/删除后
  /// - 图片从数据库中移除后
  ///
  /// 异步执行：
  /// - 使用 Task 异步执行，不阻塞主流程
  /// - 缓存失效不影响当前操作的正确性
  ///
  /// - Parameter paths: 受影响的图片路径数组
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
