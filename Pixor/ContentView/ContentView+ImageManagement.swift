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
      let refreshed = await FileOpenService.discover(from: inputs, recordRecents: false)
      let batch = ImageBatch(inputs: inputs, imageURLs: refreshed)
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
      let access = SecurityScopedAccess(url: directory)
      let normalized = [directory.standardizedFileURL]
      let uniqueSorted = await FileOpenService.discover(from: normalized, recordRecents: false)
      let batch = ImageBatch(inputs: normalized, imageURLs: uniqueSorted)
      await MainActor.run {
        securityAccess = access
        applyImageBatch(batch)
      }
    }
  }

  /// 处理来自 Finder 或 Dock 的外部打开请求
  func handleExternalImageBatch(_ batch: ImageBatch) {
    updateSecurityAccess(using: batch.inputs)
    applyImageBatch(batch)
  }

  /// 更新沙盒访问权限，保证后续读写能力
  func updateSecurityAccess(using inputs: [URL]) {
    guard let first = inputs.first else {
      securityAccess = nil
      return
    }
    let directory = first.hasDirectoryPath ? first : first.deletingLastPathComponent()
    securityAccess = SecurityScopedAccess(url: directory)
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
