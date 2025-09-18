//
//  RecentOpensManager.swift
//  Pixo
//
//  Manages recent folders with security-scoped bookmarks.
//

import Foundation
import AppKit

struct RecentFolderItem: Codable, Identifiable, Equatable {
  let id: UUID
  var path: String
  var bookmarkData: Data
  var lastOpenedAt: Date

  init(path: String, bookmarkData: Data, lastOpenedAt: Date) {
    self.id = UUID()
    self.path = path
    self.bookmarkData = bookmarkData
    self.lastOpenedAt = lastOpenedAt
  }
}

/// Manages security-scoped bookmarks for recently opened folders.
/// Stores data in UserDefaults as JSON.
@MainActor
final class RecentOpensManager: ObservableObject {
  static let shared = RecentOpensManager()

  // MARK: - Public state
  @Published private(set) var items: [RecentFolderItem] = []

  // MARK: - Private
  private let userDefaultsKey = "recentFolders.v1"
  private let maxCount = 10

  // Keep the currently accessed URL to hold security scope while in use.
  private var currentlyAccessedURL: URL?

  private init() {
    load()
  }

  // MARK: - Persistence
  private func load() {
    let defaults = UserDefaults.standard
    guard let data = defaults.data(forKey: userDefaultsKey) else {
      self.items = []
      return
    }
    do {
      let decoded = try JSONDecoder().decode([RecentFolderItem].self, from: data)
      // Sort by lastOpenedAt desc to be safe
      self.items = decoded.sorted(by: { $0.lastOpenedAt > $1.lastOpenedAt })
    } catch {
      // Corrupted data; clear it
      self.items = []
    }
  }

  private func persist() {
    do {
      let data = try JSONEncoder().encode(items)
      UserDefaults.standard.set(data, forKey: userDefaultsKey)
    } catch {
      // Ignore persistence error
    }
  }

  // MARK: - Public API

  /// Add urls (file or directory). Files will be normalized to their parent directory.
  func add(urls: [URL]) {
    let folders = uniqueFolders(from: urls)
    for folder in folders {
      add(folder: folder)
    }
  }

  /// Add a single folder to recents with security-scoped bookmark.
  func add(folder: URL) {
    guard folder.hasDirectoryPath else { return }
    let standardized = folder.standardizedFileURL

    do {
      let bookmark = try standardized.bookmarkData(
        options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
        includingResourceValuesForKeys: nil,
        relativeTo: nil
      )

      // De-duplicate by path
      items.removeAll { $0.path == standardized.path }

      let item = RecentFolderItem(
        path: standardized.path,
        bookmarkData: bookmark,
        lastOpenedAt: Date()
      )
      items.insert(item, at: 0)

      if items.count > maxCount { items.removeLast(items.count - maxCount) }
      persist()
    } catch {
      // Couldn't create bookmark; ignore
    }
  }

  /// Clear all recent items and stop any active security scope.
  func clear() {
    stopAccessingCurrentIfNeeded()
    items.removeAll()
    persist()
  }

  /// Attempt to resolve and open the given recent item.
  /// Posts `.openFolderURLRequested` notification on success.
  func open(item: RecentFolderItem) {
    guard let resolved = resolveURL(from: item) else { return }

    // Keep scope open for current folder usage
    stopAccessingCurrentIfNeeded()
    if resolved.startAccessingSecurityScopedResource() {
      currentlyAccessedURL = resolved
    }

    // Move item to top and update time
    if let index = items.firstIndex(where: { $0.id == item.id }) {
      var updated = items.remove(at: index)
      updated.lastOpenedAt = Date()
      items.insert(updated, at: 0)
      persist()
    }

    NotificationCenter.default.post(name: .openFolderURLRequested, object: resolved)
  }

  /// Reopen the last recent item (top of list).
  func reopenLast() {
    guard let first = items.first else { return }
    open(item: first)
  }

  // MARK: - Helpers
  private func uniqueFolders(from urls: [URL]) -> [URL] {
    var set: Set<String> = []
    var result: [URL] = []
    for url in urls {
      let folder = url.hasDirectoryPath ? url : url.deletingLastPathComponent()
      let key = folder.standardizedFileURL.path
      if !set.contains(key) {
        set.insert(key)
        result.append(folder)
      }
    }
    return result
  }

  private func resolveURL(from item: RecentFolderItem) -> URL? {
    var isStale = false
    do {
      let url = try URL(
        resolvingBookmarkData: item.bookmarkData,
        options: [.withSecurityScope, .withoutUI],
        relativeTo: nil,
        bookmarkDataIsStale: &isStale
      )

      if isStale {
        // Refresh bookmark
        let newData = try url.bookmarkData(
          options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
          includingResourceValuesForKeys: nil,
          relativeTo: nil
        )
        if let idx = items.firstIndex(where: { $0.id == item.id }) {
          items[idx].bookmarkData = newData
          persist()
        }
      }

      return url
    } catch {
      return nil
    }
  }

  private func stopAccessingCurrentIfNeeded() {
    currentlyAccessedURL?.stopAccessingSecurityScopedResource()
    currentlyAccessedURL = nil
  }
}
