//
//  ContentView+Deletion.swift
//

import Foundation

@MainActor
extension ContentView {
  /// 删除模式：移动到废纸篓或不可恢复的直接删除
  enum ImageDeletionMode {
    case moveToTrash
    case deletePermanently
  }

  func requestDeletion() {
    // 若已有选中图片且未在删除中，弹出确认选项
    guard let url = selectedImageURL, !isPerformingDeletion else { return }
    let hasFullAccess = FullDiskAccessChecker.hasFullDiskAccess()
    let hasScopedPermission = securityAccessGroup?.canAccess(url) == true
    if !hasFullAccess && !hasScopedPermission {
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

  func cancelDeletionRequest() {
    // 用户主动取消时清理状态
    showingDeletionOptions = false
    pendingDeletionURL = nil
  }

  func confirmDeletion(of url: URL, mode: ImageDeletionMode) {
    // 避免并发删除；关闭弹窗并进入执行状态
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

  private func executeDeletion(of url: URL, mode: ImageDeletionMode) async throws {
    // 后台线程执行磁盘操作，避免阻塞主线程
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

  private func finalizeDeletion(of url: URL) {
    // 删除成功后恢复状态，并更新图片列表与选中项
    pendingDeletionURL = nil
    isPerformingDeletion = false
    cancelOngoingExifLoad()

    guard let index = imageURLs.firstIndex(of: url) else { return }

    imageURLs.remove(at: index)

    guard !imageURLs.isEmpty else {
      selectedImageURL = nil
      imageTransform = .identity
      showingExifInfo = false
      currentExifInfo = nil
      return
    }

    let nextIndex = index < imageURLs.count ? index : imageURLs.count - 1
    selectedImageURL = imageURLs[nextIndex]
  }

  private func presentDeletionFailure(for url: URL, error: Error) {
    // 删除失败时反馈错误原因，恢复执行标记
    isPerformingDeletion = false
    pendingDeletionURL = nil
    let nsError = error as NSError
    if nsError.domain == NSCocoaErrorDomain,
       [NSFileWriteNoPermissionError, NSFileReadNoPermissionError].contains(nsError.code) {
      let hasFullAccess = FullDiskAccessChecker.hasFullDiskAccess()
      let hasScopedPermission = securityAccessGroup?.canAccess(url) == true
      if !hasFullAccess && !hasScopedPermission {
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

  private func presentFullDiskAccessRequirement(for url: URL) {
    pendingFullDiskAccessFileName = url.lastPathComponent
    showingFullDiskAccessPrompt = true
  }
}
