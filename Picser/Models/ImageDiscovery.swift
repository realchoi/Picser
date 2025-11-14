//
//  ImageDiscovery.swift
//
//  Extracted from ContentView to keep it lean.
//

import Foundation

/// 图片发现与排序。
/// 功能: 将原先 ContentView 中的图片枚举、去重、稳定排序逻辑迁出，提供 ImageDiscovery.computeImageURLs(from:)。
enum ImageDiscovery {
  /// Enumerate image URLs from mixed inputs (files or folders),
  /// de-duplicate by standardized path, and return a stable, Finder-like sorted list.
  static func computeImageURLs(from inputs: [URL], recursive: Bool) async -> [URL] {
    let imageExtensions = FormatUtils.supportedImageExtensions
    let resourceKeys: Set<URLResourceKey> = [
      .isDirectoryKey, .isRegularFileKey, .isPackageKey, .isHiddenKey, .typeIdentifierKey
    ]

    return await withCheckedContinuation { continuation in
      DispatchQueue.global(qos: .userInitiated).async {
        var collected: [URL] = []
        let fileManager = FileManager.default

        func appendIfImage(_ url: URL) {
          let ext = url.pathExtension.lowercased()
          if imageExtensions.contains(ext) {
            collected.append(url)
          }
        }

        func appendImages(in directory: URL) {
          if recursive {
            if let enumerator = fileManager.enumerator(
              at: directory,
              includingPropertiesForKeys: Array(resourceKeys),
              options: [.skipsHiddenFiles, .skipsPackageDescendants],
              errorHandler: { _, _ in true }
            ) {
              for case let fileURL as URL in enumerator {
                do {
                  let values = try fileURL.resourceValues(forKeys: resourceKeys)
                  guard values.isRegularFile == true else { continue }
                  appendIfImage(fileURL)
                } catch {
                  continue
                }
              }
            }
          } else if let items = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: Array(resourceKeys),
            options: [.skipsHiddenFiles]
          ) {
            for item in items {
              do {
                let values = try item.resourceValues(forKeys: resourceKeys)
                if values.isDirectory == true || values.isPackage == true { continue }
                guard values.isRegularFile == true else { continue }
                appendIfImage(item)
              } catch {
                continue
              }
            }
          }
        }

        for original in inputs {
          let normalized = original.standardizedFileURL
          let resourceValues = try? normalized.resourceValues(forKeys: resourceKeys)

          if resourceValues?.isDirectory == true {
            if resourceValues?.isPackage == true { continue }
            appendImages(in: normalized)
          } else if resourceValues?.isRegularFile == true || !normalized.hasDirectoryPath {
            appendIfImage(normalized)
          } else if normalized.hasDirectoryPath {
            // fallback when resourceValues not available
            appendImages(in: normalized)
          }
        }

        var seen: Set<String> = []
        var unique: [URL] = []
        unique.reserveCapacity(collected.count)
        for url in collected {
          let key = url.standardizedFileURL.path
          if !seen.contains(key) {
            seen.insert(key)
            unique.append(url)
          }
        }

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
