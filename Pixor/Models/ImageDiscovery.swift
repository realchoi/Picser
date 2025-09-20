//
//  ImageDiscovery.swift
//  Pixor
//
//  Extracted from ContentView to keep it lean.
//

import Foundation

/// 图片发现与排序。
/// 功能: 将原先 ContentView 中的图片枚举、去重、稳定排序逻辑迁出，提供 ImageDiscovery.computeImageURLs(from:)。
enum ImageDiscovery {
  /// Enumerate image URLs from mixed inputs (files or folders),
  /// de-duplicate by standardized path, and return a stable, Finder-like sorted list.
  static func computeImageURLs(from inputs: [URL]) async -> [URL] {
    // Allowed image extensions (lowercased)
    let imageExtensions = ["jpg", "jpeg", "png", "gif", "heic", "tiff", "webp"]

    return await withCheckedContinuation { continuation in
      DispatchQueue.global(qos: .userInitiated).async {
        var collected: [URL] = []
        let fm = FileManager.default

        // 1) Enumerate inputs and collect image URLs
        for url in inputs {
          if url.hasDirectoryPath {
            if let files = try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: nil) {
              collected.append(contentsOf: files.filter { imageExtensions.contains($0.pathExtension.lowercased()) })
            }
          } else if imageExtensions.contains(url.pathExtension.lowercased()) {
            collected.append(url)
          }
        }

        // 2) De-duplicate while preserving first-seen order
        var seen: [String: Bool] = [:]
        var unique: [URL] = []
        unique.reserveCapacity(collected.count)
        for url in collected {
          let key = url.standardizedFileURL.path
          if seen[key] == nil {
            seen[key] = true
            unique.append(url)
          }
        }

        // 3) Stable sort by directory then filename, Finder-like natural order
        let enumerated = unique.enumerated().map { ($0.offset, $0.element) }
        let sortedStable = enumerated.sorted { lhs, rhs in
          let (li, l) = lhs
          let (ri, r) = rhs
          let lDir = l.deletingLastPathComponent().path
          let rDir = r.deletingLastPathComponent().path

          if lDir != rDir {
            return lDir.localizedStandardCompare(rDir) == .orderedAscending
          }

          let lName = l.lastPathComponent
          let rName = r.lastPathComponent
          let nameOrder = lName.localizedStandardCompare(rName)
          if nameOrder != .orderedSame {
            return nameOrder == .orderedAscending
          }

          return li < ri
        }.map { $0.1 }

        continuation.resume(returning: sortedStable)
      }
    }
  }
}

