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
}
