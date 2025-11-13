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
  /// 带安全作用域的原始 URL，用于后续写入/删除。
  let securityScopedInputs: [URL]
  /// 通过解析得到的图片 URL 列表，按照 Finder 风格排序。
  let imageURLs: [URL]
  /// 关联的安全访问令牌集合，确保在使用期间保持目录访问权限
  let accessGroup: SecurityScopedAccessGroup
  /// 用户最初选择的图片文件（当开启"打开单个图片时加载所在目录"时使用）
  let initiallySelectedImage: URL?
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
    let scopedURLs = openPanel.urls
    guard !scopedURLs.isEmpty else { return nil }

    // 应用单图片目录扩展逻辑
    let (inputs, scopedInputs, initialImage) = await applySingleImageDirectoryExpansion(
      urls: scopedURLs,
      context: "FileOpen"
    )

    return await loadImageBatch(
      from: inputs,
      recordRecents: true,
      recursive: override,
      securityScopedInputs: scopedInputs,
      initiallySelectedImage: initialImage
    )
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

    guard !droppedInputs.isEmpty else { return nil }

    // 应用单图片目录扩展逻辑
    let (inputs, scopedInputs, initialImage) = await applySingleImageDirectoryExpansion(
      urls: droppedInputs,
      context: "Drop"
    )

    return await loadImageBatch(
      from: inputs,
      recordRecents: true,
      recursive: override,
      securityScopedInputs: scopedInputs,
      initiallySelectedImage: initialImage
    )
  }

  /// Discover image URLs from given inputs (files or folders) without touching recents.
  static func discoverImageURLs(from inputs: [URL], recursive override: Bool? = nil) async -> [URL] {
    let batch = await loadImageBatch(
      from: inputs,
      recordRecents: false,
      recursive: override,
      securityScopedInputs: nil,
      initiallySelectedImage: nil
    )
    return batch.imageURLs
  }

  /// Unified discovery: optionally record recents, then compute stable-sorted image URLs.
  static func loadImageBatch(
    from inputs: [URL],
    recordRecents: Bool,
    recursive override: Bool? = nil,
    securityScopedInputs: [URL]? = nil,
    initiallySelectedImage: URL? = nil
  ) async -> ImageBatch {
    let scoped = securityScopedInputs ?? inputs
    let accessGroup = SecurityScopedAccessGroup(urls: scoped)

    if recordRecents {
      await RecentOpensManager.shared.add(urls: inputs)
    }

    let imageURLs = await ImageDiscovery.computeImageURLs(
      from: inputs,
      recursive: resolvedRecursiveFlag(override: override)
    )

    return ImageBatch(
      inputs: inputs,
      securityScopedInputs: accessGroup.retainedURLs,
      imageURLs: imageURLs,
      accessGroup: accessGroup,
      initiallySelectedImage: initiallySelectedImage
    )
  }

  private static func resolvedRecursiveFlag(override: Bool?) -> Bool {
    if let override { return override }
    if let stored = UserDefaults.standard.object(forKey: "imageScanRecursively") as? Bool {
      return stored
    }
    return true
  }

  static func shouldLoadDirectoryForSingleImage() -> Bool {
    if let stored = UserDefaults.standard.object(forKey: "loadDirectoryForSingleImage") as? Bool {
      return stored
    }
    return false
  }

  /// 检查是否需要将单个图片扩展为加载整个目录
  /// - Parameters:
  ///   - urls: 用户选择或拖拽的 URL 列表
  ///   - context: 日志上下文（如 "FileOpen"、"Drop"、"External"）
  /// - Returns: (处理后的输入URL列表, 安全作用域URL列表, 初始选中的图片)
  @MainActor
  static func applySingleImageDirectoryExpansion(
    urls: [URL],
    context: String
  ) async -> (inputs: [URL], scopedInputs: [URL], initialImage: URL?) {
    let normalizedInputs = urls.map { $0.standardizedFileURL }

    guard shouldLoadDirectoryForSingleImage(), urls.count == 1 else {
      return (normalizedInputs, urls, nil)
    }

    let selectedURL = urls[0]
    let resourceValues = try? selectedURL.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey])

    guard resourceValues?.isDirectory == false,
          resourceValues?.isRegularFile == true else {
      return (normalizedInputs, urls, nil)
    }

    if let result = await requestDirectoryAccess(for: selectedURL, context: context) {
      return ([result.directory], [result.scopedURL], result.initialImage)
    }

    return (normalizedInputs, urls, nil)
  }

  /// 尝试获取单个图片所在目录的访问权限
  /// - Parameters:
  ///   - selectedImageURL: 用户选择的单个图片文件
  ///   - context: 日志上下文（如 "FileOpen"、"Drop"、"External"）
  ///   - presentDialog: 是否允许弹出授权对话框
  /// - Returns: 成功时返回目录 URL、安全作用域 URL 和初始选中的图片；失败返回 nil
  @MainActor
  static func requestDirectoryAccess(
    for selectedImageURL: URL,
    context: String,
    presentDialog: Bool = true
  ) async -> (directory: URL, scopedURL: URL, initialImage: URL)? {
    let parentDirectory = selectedImageURL.deletingLastPathComponent()
    let parentPath = parentDirectory.standardizedFileURL.path

    // 策略 1: 检查是否有已保存的 bookmark
    if let bookmarkedURL = DirectoryBookmarkManager.shared.resolveBookmark(for: parentPath) {
      print("[\(context)] Using saved bookmark for: \(parentPath)")
      return (bookmarkedURL.standardizedFileURL, bookmarkedURL, selectedImageURL.standardizedFileURL)
    }

    // 策略 2: 尝试直接访问父目录
    let didStartAccess = selectedImageURL.startAccessingSecurityScopedResource()
    defer {
      if didStartAccess {
        selectedImageURL.stopAccessingSecurityScopedResource()
      }
    }

    if let _ = try? FileManager.default.contentsOfDirectory(
      at: parentDirectory,
      includingPropertiesForKeys: [.isRegularFileKey],
      options: [.skipsHiddenFiles]
    ) {
      print("[\(context)] Direct access to parent directory succeeded, saving bookmark")
      DirectoryBookmarkManager.shared.saveBookmark(for: parentDirectory)
      return (parentDirectory.standardizedFileURL, selectedImageURL, selectedImageURL.standardizedFileURL)
    }

    // 策略 3: 弹出对话框请求权限
    guard presentDialog else {
      print("[\(context)] Cannot access parent directory, dialog not allowed")
      return nil
    }

    print("[\(context)] Direct access failed, requesting directory permission")
    let dirPanel = NSOpenPanel()
    dirPanel.canChooseFiles = false
    dirPanel.canChooseDirectories = true
    dirPanel.allowsMultipleSelection = false
    dirPanel.directoryURL = parentDirectory
    dirPanel.message = L10n.string("directory_access_for_single_image_message")
    dirPanel.prompt = L10n.string("directory_access_grant_button")

    guard dirPanel.runModal() == .OK, let dirURL = dirPanel.url else {
      print("[\(context)] User cancelled directory access")
      return nil
    }

    print("[\(context)] User granted directory access, saving bookmark")
    DirectoryBookmarkManager.shared.saveBookmark(for: dirURL)
    return (dirURL.standardizedFileURL, dirURL, selectedImageURL.standardizedFileURL)
  }
}
