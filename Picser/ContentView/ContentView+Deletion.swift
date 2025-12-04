//
//  ContentView+Deletion.swift
//

import Foundation
import SwiftUI

@MainActor
extension ContentView {
  /// 删除模式：移动到废纸篓或不可恢复的直接删除
  enum ImageDeletionMode {
    case moveToTrash
    case deletePermanently
  }

  /// 针对当前选中图片触发删除流程，并在缺少权限时直接提示用户
  func requestDeletion() {
    guard let url = selectedImageURL, !isPerformingDeletion else { return }
    if !hasDeletionPrivilege(for: url) {
      presentFullDiskAccessRequirement(for: url)
      return
    }
    if appSettings.deleteConfirmationEnabled {
      pendingDeletionURL = url
      showingDeletionOptions = true
    } else {
      confirmDeletion(of: url, mode: .moveToTrash)
    }
  }

  /// 用户取消删除时重置弹窗与待处理 URL
  func cancelDeletionRequest() {
    showingDeletionOptions = false
    pendingDeletionURL = nil
  }

  /// 根据用户选择的模式执行删除操作，期间屏蔽重复点击
  func confirmDeletion(of url: URL, mode: ImageDeletionMode) {
    guard !isPerformingDeletion else { return }
    pendingDeletionURL = nil
    showingDeletionOptions = false
    isPerformingDeletion = true

    Task {
      do {
        try await executeDeletion(of: url, mode: mode)
        finalizeDeletion(of: url)
      } catch {
        presentDeletionFailure(for: url, error: error)
      }
    }
  }

  /// 在后台线程执行删除操作，并对移动到废纸篓失败时进行降级重试
  private func executeDeletion(of url: URL, mode: ImageDeletionMode) async throws {
    try await withCheckedThrowingContinuation { continuation in
      DispatchQueue.global(qos: .userInitiated).async {
        do {
          let work = {
            switch mode {
            case .moveToTrash:
              var resultingURL: NSURL?
              try FileManager.default.trashItem(at: url, resultingItemURL: &resultingURL)
            case .deletePermanently:
              try FileManager.default.removeItem(at: url)
            }
          }

          if let group = securityAccessGroup {
            try group.withScopedAccess(to: url, perform: work)
          } else {
            try work()
          }

          continuation.resume(returning: ())
        } catch {
          // 若移动到废纸篓失败，尝试降级为直接删除
          if mode == .moveToTrash {
            do {
              if let group = securityAccessGroup {
                try group.withScopedAccess(to: url) {
                  try FileManager.default.removeItem(at: url)
                }
              } else {
                try FileManager.default.removeItem(at: url)
              }
              continuation.resume(returning: ())
            } catch {
              // 降级策略依然失败，则将原始错误反馈给上层
              continuation.resume(throwing: error)
            }
          } else {
            continuation.resume(throwing: error)
          }
        }
      }
    }
  }

  /// 删除成功后恢复状态并更新图片列表及选中项
  private func finalizeDeletion(of url: URL) {
    pendingDeletionURL = nil
    isPerformingDeletion = false
    cancelOngoingExifLoad()

    guard let index = imageURLs.firstIndex(of: url) else { return }

    imageURLs.remove(at: index)

    let path = url.standardizedFileURL.path
    // 删除图片后同步清理标签缓存，保持 UI 状态一致
    tagService.removeAssignments(for: [path])
    Task.detached { [tagService] in
      try? await TagRepository.shared.removeImage(at: path)
      await tagService.refreshAllTags(immediate: true)
      await tagService.rebuildScopedTags()
    }

    guard !imageURLs.isEmpty else {
      selectedImageURL = nil
      imageTransform = .identity
      withAnimation(Motion.Anim.drawer) {
        showingExifInfo = false
      }
      currentExifInfo = nil
      return
    }

    let pool = visibleImageURLs  // 删除后重新基于筛选结果决定下一张
    guard !pool.isEmpty else {
      selectedImageURL = nil
      return
    }
    // 若当前索引超出范围，则向前回退到最后一个可见元素
    let nextIndex = min(max(index, 0), pool.count - 1)
    selectedImageURL = pool[nextIndex]
  }

  /// 统一处理删除失败场景，优先提示权限问题，其次回退到通用错误弹窗
  private func presentDeletionFailure(for url: URL, error: Error) {
    isPerformingDeletion = false
    pendingDeletionURL = nil
    let nsError = error as NSError
    if nsError.domain == NSCocoaErrorDomain,
       [NSFileWriteNoPermissionError, NSFileReadNoPermissionError].contains(nsError.code) {
      if !hasDeletionPrivilege(for: url) {
        presentFullDiskAccessRequirement(for: url)
        return
      }
    }

    let title = L10n.string("delete_failure_title")
    let template = L10n.string("delete_failure_message")
    let message = String(
      format: template,
      url.lastPathComponent,
      nsError.localizedDescription
    )
    alertContent = AlertContent(title: title, message: message)
  }

  /// 引导用户为目标文件授予完整磁盘访问权限
  private func presentFullDiskAccessRequirement(for url: URL) {
    pendingFullDiskAccessFileName = url.lastPathComponent
    showingFullDiskAccessPrompt = true
  }

  /// 综合检测完整磁盘访问与安全作用域，判定当前是否能够删除目标文件
  private func hasDeletionPrivilege(for url: URL) -> Bool {
    if FullDiskAccessChecker.hasFullDiskAccess() {
      return true
    }
    if let group = securityAccessGroup, group.hasDeletePermission(for: url) {
      return true
    }
    return FileManager.default.isDeletableFile(atPath: url.path)
  }

  // MARK: - 批量删除功能

  /// 请求批量删除筛选结果
  ///
  /// 触发批量删除流程，检查权限并显示确认对话框。
  ///
  /// 执行流程：
  /// 1. **验证状态**：确保有图片且未在执行删除
  /// 2. **权限检查**：检查所有图片的删除权限
  /// 3. **权限不足处理**：如有无权限的文件，提示用户授予权限
  /// 4. **显示确认对话框**：权限充足时显示批量删除确认对话框
  ///
  /// 使用场景：
  /// - 用户在筛选面板点击"删除 N 张图片"按钮
  /// - 用户在标签管理界面选择删除某个标签的所有图片
  func requestBatchDeletion() {
    let urls = visibleImageURLs
    guard !urls.isEmpty, !isPerformingBatchDeletion else { return }

    // 检查权限
    let unprivilegedURLs = urls.filter { !hasDeletionPrivilege(for: $0) }
    if !unprivilegedURLs.isEmpty {
      presentFullDiskAccessRequirementForBatch(unprivilegedURLs)
      return
    }

    pendingBatchDeletionURLs = urls
    batchDeletionFailedURLs = []
    showingBatchDeletionConfirmation = true
  }

  /// 确认并执行批量删除
  ///
  /// 执行批量删除操作，显示进度并处理失败情况。
  ///
  /// 执行流程：
  /// 1. **准备阶段**：
  ///    - 保存待删除列表
  ///    - 清空失败列表
  ///    - 设置执行标志
  ///    - 重置进度为 0
  /// 2. **删除阶段**：
  ///    - 逐个删除图片
  ///    - 更新进度（每删除一张更新一次）
  ///    - 记录失败的文件和错误信息
  /// 3. **清理阶段**：
  ///    - 从列表中移除成功删除的图片
  ///    - 清理标签缓存
  ///    - 同步数据库
  ///    - 可选：清理孤立标签
  /// 4. **结果反馈**：
  ///    - 全部成功：关闭对话框，显示成功提示
  ///    - 部分失败：显示失败列表，允许重试
  ///
  /// 使用场景：
  /// - 用户在确认对话框中点击"移到废纸篓"或"永久删除"
  ///
  /// - Parameters:
  ///   - mode: 删除模式（废纸篓/永久删除）
  ///   - removeOrphanTags: 是否同时删除孤立标签
  func confirmBatchDeletion(mode: ImageDeletionMode, removeOrphanTags: Bool) async {
    guard !isPerformingBatchDeletion else { return }

    let urls = pendingBatchDeletionURLs
    guard !urls.isEmpty else { return }

    // 准备阶段
    await MainActor.run {
      isPerformingBatchDeletion = true
      batchDeletionProgress = 0.0
      batchDeletionFailedURLs = []
    }

    var successURLs: [URL] = []
    var failedItems: [(URL, Error)] = []

    // 删除阶段
    for (index, url) in urls.enumerated() {
      do {
        try await executeDeletion(of: url, mode: mode)
        successURLs.append(url)
      } catch {
        failedItems.append((url, error))
      }

      // 更新进度
      let progress = Double(index + 1) / Double(urls.count)
      await MainActor.run {
        batchDeletionProgress = progress
      }
    }

    // 清理阶段
    await finalizeBatchDeletion(successURLs: successURLs, failedItems: failedItems)

    // 清理孤立标签（可选）
    if removeOrphanTags {
      await tagService.purgeUnusedTags()
    }

    // 结果反馈
    await MainActor.run {
      isPerformingBatchDeletion = false

      if failedItems.isEmpty {
        // 全部成功：关闭对话框
        showingBatchDeletionConfirmation = false
        pendingBatchDeletionURLs = []
        presentBatchDeletionSuccess(count: successURLs.count)
      } else {
        // 部分失败：显示失败列表
        batchDeletionFailedURLs = failedItems
        // 对话框保持打开，显示失败视图
      }
    }
  }

  /// 批量删除后的清理工作
  ///
  /// 更新界面状态、清理缓存、同步数据库。
  ///
  /// 执行流程：
  /// 1. **移除图片**：从 imageURLs 中移除成功删除的图片
  /// 2. **清理标签缓存**：调用 tagService.removeAssignments 清理缓存
  /// 3. **同步数据库**：异步删除数据库记录
  /// 4. **刷新标签统计**：更新标签使用统计
  /// 5. **更新选中项**：选中下一张可见图片
  ///
  /// 注意事项：
  /// - 在主线程更新 UI 状态
  /// - 数据库操作在后台线程执行
  /// - 确保选中项在可见列表中
  ///
  /// - Parameters:
  ///   - successURLs: 成功删除的图片 URL 列表
  ///   - failedItems: 失败的图片和错误信息列表
  private func finalizeBatchDeletion(successURLs: [URL], failedItems: [(URL, Error)]) async {
    let successSet = Set(successURLs)

    await MainActor.run {
      // 从列表中移除成功删除的图片
      imageURLs.removeAll { successSet.contains($0) }

      // 清理标签缓存
      let paths = successURLs.map { $0.standardizedFileURL.path }
      tagService.removeAssignments(for: paths)

      // 更新选中项
      updateSelectionAfterBatchDeletion()

      // 取消正在进行的 EXIF 加载
      if let selected = selectedImageURL, successSet.contains(selected) {
        cancelOngoingExifLoad()
      }
    }

    // 异步同步数据库
    Task.detached { [tagService] in
      let paths = successURLs.map { $0.standardizedFileURL.path }
      for path in paths {
        try? await TagRepository.shared.removeImage(at: path)
      }
      await tagService.refreshAllTags(immediate: true)
      await tagService.rebuildScopedTags()
    }
  }

  /// 批量删除后更新选中项
  ///
  /// 确保选中项在可见图片列表中，如果当前选中的图片被删除，则选中下一张。
  private func updateSelectionAfterBatchDeletion() {
    guard !imageURLs.isEmpty else {
      selectedImageURL = nil
      imageTransform = .identity
      withAnimation(Motion.Anim.drawer) {
        showingExifInfo = false
      }
      currentExifInfo = nil
      return
    }

    let pool = visibleImageURLs
    guard !pool.isEmpty else {
      selectedImageURL = nil
      return
    }

    // 如果当前选中的图片还在列表中，保持选中
    if let current = selectedImageURL, pool.contains(current) {
      return
    }

    // 否则选中第一张可见图片
    selectedImageURL = pool.first
  }

  /// 显示批量删除成功提示
  ///
  /// 使用 Toast 或 Alert 显示删除成功的反馈。
  ///
  /// - Parameter count: 成功删除的图片数量
  private func presentBatchDeletionSuccess(count: Int) {
    let title = L10n.string("batch_delete_success_title")
    let message = String(format: L10n.string("batch_delete_success_message"), count)
    alertContent = AlertContent(title: title, message: message)
  }

  /// 引导用户为批量删除授予完整磁盘访问权限
  ///
  /// 当部分文件无权限删除时，提示用户授予完整磁盘访问权限。
  ///
  /// - Parameter urls: 无权限的文件列表
  private func presentFullDiskAccessRequirementForBatch(_ urls: [URL]) {
    let title = L10n.string("batch_delete_permission_title")
    let template = L10n.string("batch_delete_permission_message")
    let message = String(format: template, urls.count)
    alertContent = AlertContent(title: title, message: message)
  }

  /// 重试批量删除失败的文件
  ///
  /// 只重试之前失败的文件，不包括成功删除的文件。
  func retryFailedBatchDeletion() async {
    let failedURLs = batchDeletionFailedURLs.map { $0.0 }
    guard !failedURLs.isEmpty else { return }

    // 重新设置待删除列表为失败的文件
    await MainActor.run {
      pendingBatchDeletionURLs = failedURLs
      batchDeletionFailedURLs = []
    }

    // 使用之前选择的删除模式（默认废纸篓）
    await confirmBatchDeletion(mode: .moveToTrash, removeOrphanTags: false)
  }
}
