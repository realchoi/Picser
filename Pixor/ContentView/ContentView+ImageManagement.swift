//
//  ContentView+ImageManagement.swift
//  Pixor
//
//  Created by Codex on 2025/2/14.
//

import Foundation
import SwiftUI

@MainActor
extension ContentView {
  /// 显示一个通用警告弹窗
  func presentAlert(_ content: AlertContent) {
    alertContent = content
  }

  /// 应用新的图片批次并根据上下文保持选中状态
  func applyImageBatch(_ batch: ImageBatch, preserveSelection selection: URL? = nil, previouslySelectedIndex: Int? = nil) {
    securityAccessGroup = batch.accessGroup
    currentSourceInputs = batch.inputs
    imageURLs = batch.imageURLs

    guard !batch.imageURLs.isEmpty else {
      selectedImageURL = nil
      imageTransform = .identity
      isCropping = false
      return
    }

    if let selection, batch.imageURLs.contains(selection) {
      selectedImageURL = selection
      return
    }

    if let index = previouslySelectedIndex {
      let clamped = min(max(index, 0), batch.imageURLs.count - 1)
      selectedImageURL = batch.imageURLs[clamped]
      return
    }

    selectedImageURL = batch.imageURLs.first
  }

  /// 重新扫描当前输入源并同步图片列表
  func refreshCurrentInputs() {
    guard !currentSourceInputs.isEmpty else { return }
    let inputs = currentSourceInputs

    Task {
      let batch = await FileOpenService.loadImageBatch(
        from: inputs,
        recordRecents: false,
        recursive: appSettings.imageScanRecursively
      )
      await MainActor.run {
        let currentSelection = selectedImageURL
        let previousIndex = currentSelection.flatMap { imageURLs.firstIndex(of: $0) }
        applyImageBatch(batch, preserveSelection: currentSelection, previouslySelectedIndex: previousIndex)
      }
    }
  }

  /// 按选中项预取临近图片以提升切换体验
  func prefetchNeighbors(around url: URL) {
    guard let idx = imageURLs.firstIndex(of: url) else { return }
    var neighbors: [URL] = []
    if idx > 0 { neighbors.append(imageURLs[idx - 1]) }
    if idx + 1 < imageURLs.count { neighbors.append(imageURLs[idx + 1]) }
    ImageLoader.shared.prefetch(urls: neighbors)
  }

  /// 打开解析后的 URL，并根据所在目录刷新图片批次
  func openResolvedURL(_ url: URL) {
    Task {
      let directory = url.hasDirectoryPath ? url : url.deletingLastPathComponent()
      let normalized = [directory.standardizedFileURL]
      let batch = await FileOpenService.loadImageBatch(
        from: normalized,
        recordRecents: false,
        recursive: appSettings.imageScanRecursively
      )
      await MainActor.run {
        applyImageBatch(batch)
      }
    }
  }

  /// 处理来自 Finder 或 Dock 的外部打开请求
  func handleExternalImageBatch(_ batch: ImageBatch) {
    applyImageBatch(batch)
  }
}

final class SecurityScopedAccess {
  private let url: URL
  private let didStart: Bool

  init(url: URL) {
    self.url = url
    self.didStart = url.startAccessingSecurityScopedResource()
  }

  deinit {
    if didStart {
      url.stopAccessingSecurityScopedResource()
    }
  }
}

/// 批量管理多个目录的沙盒访问令牌，确保在读取文件前先启动安全范围
final class SecurityScopedAccessGroup {
  private var accessors: [String: SecurityScopedAccess] = [:]
  private(set) var directories: [URL]

  init(urls: [URL]) {
    self.directories = SecurityScopedAccessGroup.uniqueDirectories(from: urls)
    for directory in directories {
      accessors[directory.path] = SecurityScopedAccess(url: directory)
    }
  }

  /// 根据给定 URL 列表去重并规范化出目录列表
  static func uniqueDirectories(from urls: [URL]) -> [URL] {
    var seen: Set<String> = []
    var result: [URL] = []
    for url in urls {
      let directory = (url.hasDirectoryPath ? url : url.deletingLastPathComponent()).standardizedFileURL
      let key = directory.path
      if !seen.contains(key) {
        seen.insert(key)
        result.append(directory)
      }
    }
    return result
  }

  /// 为额外的 URL 扩展安全访问令牌，避免重复申请
  func extend(with urls: [URL]) {
    let newDirectories = SecurityScopedAccessGroup.uniqueDirectories(from: urls)
    for directory in newDirectories {
      let key = directory.path
      if accessors[key] == nil {
        accessors[key] = SecurityScopedAccess(url: directory)
        directories.append(directory)
      }
    }
  }
}
