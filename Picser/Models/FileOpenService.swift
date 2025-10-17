//
//  FileOpenService.swift
//
//  Extracted from ContentView to encapsulate file/folder opening and drop handling.
//

import AppKit
import Foundation
import UniformTypeIdentifiers

/// 表示一次图片集合加载的结果，包含原始输入和解析出的图片列表。
struct ImageBatch {
  /// 用户选择或拖拽的原始 URL（可能是文件或文件夹）。
  let inputs: [URL]
  /// 通过解析得到的图片 URL 列表，按照 Finder 风格排序。
  let imageURLs: [URL]
  /// 关联的安全访问令牌集合，确保在使用期间保持目录访问权限
  let accessGroup: SecurityScopedAccessGroup
}

/// 文件打开服务，处理打开文件/文件夹和拖拽操作。
enum FileOpenService {
  /// 弹出打开面板选择文件或文件夹，并返回原始输入与解析出的图片集合。
  /// - Returns: 若用户取消则返回 nil；否则返回包含来源 URL 与排序后图片 URL 的批次。
  @MainActor
  static func openFileOrFolder(recursive override: Bool? = nil) async -> ImageBatch? {
    let openPanel = NSOpenPanel()
    openPanel.canChooseFiles = true
    openPanel.canChooseDirectories = true
    openPanel.allowsMultipleSelection = true
    openPanel.allowedContentTypes = [UTType.image]

    guard openPanel.runModal() == .OK else { return nil }
    let urls = openPanel.urls.map { $0.standardizedFileURL }
    guard !urls.isEmpty else { return nil }

    return await loadImageBatch(from: urls, recordRecents: true, recursive: override)
  }

  /// 处理拖拽提供者，记录最近项目并返回图片集合。
  /// - Parameter providers: 来自 onDrop 的提供者列表。
  /// - Returns: 若成功解析，则返回包含来源 URL 与排序后图片 URL 的批次；否则为 nil。
  static func processDropProviders(_ providers: [NSItemProvider], recursive override: Bool? = nil) async -> ImageBatch? {
    guard !providers.isEmpty else { return nil }

    let droppedInputs: [URL] = await withCheckedContinuation { (continuation: CheckedContinuation<[URL], Never>) in
      let group = DispatchGroup()
      var urls: [URL] = []

      for provider in providers {
        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
          group.enter()
          provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
            defer { group.leave() }
            if let url = item as? URL {
              urls.append(url)
            } else if let data = item as? Data,
                      let str = String(data: data, encoding: .utf8),
                      let url = URL(string: str) {
              urls.append(url)
            }
          }
        }
      }

      group.notify(queue: .global(qos: .userInitiated)) {
        continuation.resume(returning: urls)
      }
    }

    let normalized = droppedInputs.map { $0.standardizedFileURL }
    guard !normalized.isEmpty else { return nil }
    return await loadImageBatch(from: normalized, recordRecents: true, recursive: override)
  }

  /// Discover image URLs from given inputs (files or folders) without touching recents.
  static func discoverImageURLs(from inputs: [URL], recursive override: Bool? = nil) async -> [URL] {
    let batch = await loadImageBatch(from: inputs, recordRecents: false, recursive: override)
    return batch.imageURLs
  }

  /// Unified discovery: optionally record recents, then compute stable-sorted image URLs.
  static func loadImageBatch(from inputs: [URL], recordRecents: Bool, recursive override: Bool? = nil) async -> ImageBatch {
    let accessGroup = SecurityScopedAccessGroup(urls: inputs)
    if recordRecents {
      await RecentOpensManager.shared.add(urls: inputs)
    }
    let imageURLs = await ImageDiscovery.computeImageURLs(
      from: inputs,
      recursive: resolvedRecursiveFlag(override: override)
    )
    return ImageBatch(inputs: inputs, imageURLs: imageURLs, accessGroup: accessGroup)
  }

  private static func resolvedRecursiveFlag(override: Bool?) -> Bool {
    if let override { return override }
    if let stored = UserDefaults.standard.object(forKey: "imageScanRecursively") as? Bool {
      return stored
    }
    return true
  }
}
