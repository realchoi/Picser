//
//  FileOpenService.swift
//  PicTube
//
//  Extracted from ContentView to encapsulate file/folder opening and drop handling.
//

import AppKit
import Foundation
import UniformTypeIdentifiers

/// 文件打开服务，处理打开文件/文件夹和拖拽操作。
enum FileOpenService {
  /// Show an open panel to select files or folders and return discovered image URLs.
  /// - Returns: Stable-sorted image URLs or empty array if user cancels or none found.
  @MainActor
  static func openFileOrFolder() async -> [URL] {
    let openPanel = NSOpenPanel()
    openPanel.canChooseFiles = true
    openPanel.canChooseDirectories = true
    openPanel.allowsMultipleSelection = true
    openPanel.allowedContentTypes = [UTType.image]

    guard openPanel.runModal() == .OK else { return [] }
    let urls = openPanel.urls
    guard !urls.isEmpty else { return [] }

    return await discover(from: urls, recordRecents: true)
  }

  /// Process dropped item providers, record recents, and return discovered image URLs.
  /// - Parameter providers: Providers from onDrop.
  /// - Returns: Stable-sorted image URLs (may be empty).
  static func processDropProviders(_ providers: [NSItemProvider]) async -> [URL] {
    guard !providers.isEmpty else { return [] }

    let droppedURLs: [URL] = await withCheckedContinuation { (continuation: CheckedContinuation<[URL], Never>) in
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

    guard !droppedURLs.isEmpty else { return [] }
    return await discover(from: droppedURLs, recordRecents: true)
  }

  /// Discover image URLs from given inputs (files or folders) without touching recents.
  static func discoverImageURLs(from inputs: [URL]) async -> [URL] {
    return await discover(from: inputs, recordRecents: false)
  }

  /// Unified discovery: optionally record recents, then compute stable-sorted image URLs.
  static func discover(from inputs: [URL], recordRecents: Bool) async -> [URL] {
    if recordRecents {
      RecentOpensManager.shared.add(urls: inputs)
    }
    return await ImageDiscovery.computeImageURLs(from: inputs)
  }
}
