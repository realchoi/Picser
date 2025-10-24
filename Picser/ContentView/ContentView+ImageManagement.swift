//
//  ContentView+ImageManagement.swift
//
//  Created by Eric Cai on 2025/9/19.
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
    currentSecurityScopedInputs = batch.securityScopedInputs
    imageURLs = batch.imageURLs

    guard !batch.imageURLs.isEmpty else {
      selectedImageURL = nil
      imageTransform = .identity
      isCropping = false
      currentSecurityScopedInputs = batch.securityScopedInputs
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
    let scopedInputs = currentSecurityScopedInputs

    Task {
      let batch = await FileOpenService.loadImageBatch(
        from: inputs,
        recordRecents: false,
        recursive: appSettings.imageScanRecursively,
        securityScopedInputs: scopedInputs.isEmpty ? nil : scopedInputs
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
    Task { @MainActor in
      let directoryURL = url.hasDirectoryPath ? url : url.deletingLastPathComponent()
      let standardizedDirectory = directoryURL.standardizedFileURL

      var scopedInputs: [URL] = []
      var seenPaths: Set<String> = []
      func appendScoped(_ candidate: URL) {
        let key = candidate.standardizedFileURL.path
        guard !seenPaths.contains(key) else { return }
        seenPaths.insert(key)
        scopedInputs.append(candidate)
      }

      appendScoped(directoryURL)

      if let retained = securityAccessGroup?.retainedURLs {
        let directoryPath = standardizedDirectory.path
        let directoryPrefix = directoryPath.hasSuffix("/") ? directoryPath : directoryPath + "/"
        for candidate in retained {
          let candidatePath = candidate.standardizedFileURL.path
          if candidatePath == directoryPath || candidatePath.hasPrefix(directoryPrefix) {
            appendScoped(candidate)
          }
        }
      }

      let batch = await FileOpenService.loadImageBatch(
        from: [standardizedDirectory],
        recordRecents: false,
        recursive: appSettings.imageScanRecursively,
        securityScopedInputs: scopedInputs
      )
      applyImageBatch(batch)
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

/// 批量管理安全作用域 URL，确保文件操作具备读写权限
final class SecurityScopedAccessGroup {
  private var accessors: [String: SecurityScopedAccess] = [:]
  private var scopedLookup: [String: URL] = [:]

  init(urls: [URL]) {
    extend(with: urls)
  }

  /// 将新的安全作用域 URL 添加到当前集合并保持令牌有效
  func extend(with urls: [URL]) {
    for url in urls {
      let key = Self.key(for: url)
      guard accessors[key] == nil else { continue }
      scopedLookup[key] = url
      accessors[key] = SecurityScopedAccess(url: url)
    }
  }

  /// 判断是否已经拥有访问指定 URL 的安全作用域
  func canAccess(_ url: URL) -> Bool {
    lookup(for: url) != nil
  }

  /// 通过开启对应安全作用域，判断是否具备删除目标文件的权限
  func hasDeletePermission(for url: URL) -> Bool {
    withScopedAccess(to: url) {
      FileManager.default.isDeletableFile(atPath: url.path)
    }
  }

  /// 在指定 URL 的安全作用域内执行传入任务，保证读写权限有效
  func withScopedAccess<T>(to url: URL, perform work: () throws -> T) rethrows -> T {
    if let secured = lookup(for: url), let token = accessors[Self.key(for: secured)] {
      return try withExtendedLifetime(token) {
        try work()
      }
    }

    let fallback = SecurityScopedAccess(url: url)
    return try withExtendedLifetime(fallback) {
      try work()
    }
  }

  /// 返回当前持有的安全作用域 URL 列表，便于调用方传递或持久化
  var retainedURLs: [URL] {
    Array(scopedLookup.values)
  }

  /// 在缓存中查找能够覆盖目标路径的安全作用域 URL
  private func lookup(for url: URL) -> URL? {
    var current = url.standardizedFileURL
    while true {
      let key = Self.key(for: current)
      if let match = scopedLookup[key] {
        return match
      }
      let parent = current.deletingLastPathComponent()
      if parent.path == current.path || parent.path.isEmpty {
        break
      }
      current = parent
    }
    return nil
  }

  /// 对安全作用域 URL 进行标准化，作为查找字典的键
  private static func key(for url: URL) -> String {
    url.standardizedFileURL.path
  }
}
