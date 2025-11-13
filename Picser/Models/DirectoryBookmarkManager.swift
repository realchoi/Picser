//
//  DirectoryBookmarkManager.swift
//
//  管理目录的 Security-Scoped Bookmarks，记住用户已授权的目录
//

import Foundation

/// 管理目录书签，实现"记住已授权目录"的功能
final class DirectoryBookmarkManager {
  static let shared = DirectoryBookmarkManager()

  private let bookmarksKey = "DirectoryBookmarks"
  private var bookmarkCache: [String: Data] = [:]

  private init() {
    loadBookmarks()
  }

  /// 保存目录的 security-scoped bookmark
  func saveBookmark(for directoryURL: URL) {
    let key = directoryURL.standardizedFileURL.path

    do {
      let bookmarkData = try directoryURL.bookmarkData(
        options: .withSecurityScope,
        includingResourceValuesForKeys: nil,
        relativeTo: nil
      )

      bookmarkCache[key] = bookmarkData
      persistBookmarks()

      print("[Bookmark] Saved bookmark for: \(key)")
    } catch {
      print("[Bookmark] Failed to save bookmark for \(key): \(error)")
    }
  }

  /// 尝试从已保存的 bookmark 中恢复目录 URL
  /// - Returns: 如果目录已被授权且 bookmark 有效，返回可用的 URL；否则返回 nil
  func resolveBookmark(for directoryPath: String) -> URL? {
    guard let bookmarkData = bookmarkCache[directoryPath] else {
      return nil
    }

    var isStale = false
    do {
      let url = try URL(
        resolvingBookmarkData: bookmarkData,
        options: .withSecurityScope,
        relativeTo: nil,
        bookmarkDataIsStale: &isStale
      )

      if isStale {
        print("[Bookmark] Bookmark is stale for: \(directoryPath), removing")
        bookmarkCache.removeValue(forKey: directoryPath)
        persistBookmarks()
        return nil
      }

      print("[Bookmark] Resolved bookmark for: \(directoryPath)")
      return url
    } catch {
      print("[Bookmark] Failed to resolve bookmark for \(directoryPath): \(error)")
      bookmarkCache.removeValue(forKey: directoryPath)
      persistBookmarks()
      return nil
    }
  }

  /// 检查某个目录是否已有有效的 bookmark
  func hasValidBookmark(for directoryURL: URL) -> Bool {
    let key = directoryURL.standardizedFileURL.path
    return resolveBookmark(for: key) != nil
  }

  /// 清除所有已保存的 bookmarks
  func clearAllBookmarks() {
    bookmarkCache.removeAll()
    persistBookmarks()
    print("[Bookmark] Cleared all bookmarks")
  }

  /// 清除指定目录的 bookmark
  func removeBookmark(for directoryURL: URL) {
    let key = directoryURL.standardizedFileURL.path
    bookmarkCache.removeValue(forKey: key)
    persistBookmarks()
    print("[Bookmark] Removed bookmark for: \(key)")
  }

  /// 获取当前保存的书签数量
  func getBookmarkCount() -> Int {
    return bookmarkCache.count
  }

  /// 获取所有书签占用的空间（估算值，单位：字节）
  func getBookmarkSize() -> Int64 {
    var totalSize: Int64 = 0
    for (_, data) in bookmarkCache {
      totalSize += Int64(data.count)
    }
    return totalSize
  }

  /// 从 UserDefaults 加载已保存的 bookmarks
  private func loadBookmarks() {
    guard let data = UserDefaults.standard.data(forKey: bookmarksKey) else {
      return
    }

    do {
      if let decoded = try NSKeyedUnarchiver.unarchivedObject(
        ofClasses: [NSDictionary.self, NSString.self, NSData.self],
        from: data
      ) as? [String: Data] {
        bookmarkCache = decoded
        print("[Bookmark] Loaded \(decoded.count) bookmarks")
      }
    } catch {
      print("[Bookmark] Failed to load bookmarks: \(error)")
    }
  }

  /// 将当前的 bookmarks 持久化到 UserDefaults
  private func persistBookmarks() {
    do {
      let data = try NSKeyedArchiver.archivedData(
        withRootObject: bookmarkCache,
        requiringSecureCoding: true
      )
      UserDefaults.standard.set(data, forKey: bookmarksKey)
      print("[Bookmark] Persisted \(bookmarkCache.count) bookmarks")
    } catch {
      print("[Bookmark] Failed to persist bookmarks: \(error)")
    }
  }
}
