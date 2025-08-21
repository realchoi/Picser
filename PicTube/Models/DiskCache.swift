//
//  DiskCache.swift
//  PicTube
//
//  Created by Eric Cai on 2025/8/21.
//

import AppKit
import CryptoKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// 简单的磁盘图片缓存（线程安全），用于存储下采样后的图片与缩略图
actor DiskCache {
  static let shared = DiskCache()

  private let baseURL: URL
  private let fileManager = FileManager.default
  private var byteLimit: Int = 1_000_000_000  // 默认 1GB，可调整

  private init() {
    let caches = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first!
    let dir = caches.appendingPathComponent("PicTube/ImageCache", isDirectory: true)
    if !fileManager.fileExists(atPath: dir.path) {
      try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
    }
    baseURL = dir
  }

  /// 返回磁盘缓存目录
  func cacheDirectoryURL() -> URL { baseURL }

  func setByteLimit(_ bytes: Int) {
    byteLimit = max(64 * 1_024 * 1_024, bytes)
  }

  /// 依据键检索图片文件 URL（若存在则返回）
  func retrieve(forKey key: String) -> URL? {
    if let url = existingFileURL(forKey: key) {
      // 更新 mtime 以便 LRU
      try? fileManager.setAttributes([.modificationDate: Date()], ofItemAtPath: url.path)
      return url
    }
    return nil
  }

  /// 存储图片到磁盘，并根据是否含 alpha 选择 JPEG 或 PNG
  func store(image: NSImage, forKey key: String) {
    guard let cg = image.cgImageForCurrentRepresentation() else { return }
    let hasAlpha =
      cg.alphaInfo == .premultipliedLast || cg.alphaInfo == .premultipliedFirst
      || cg.alphaInfo == .last || cg.alphaInfo == .first || cg.alphaInfo == .alphaOnly

    let ext = hasAlpha ? "png" : "jpg"
    let dstURL = fileURL(forKey: key, ext: ext)

    if let data = encode(cgImage: cg, ext: ext) {
      do {
        try data.write(to: dstURL, options: .atomic)
        // 触发一次简单的修剪
        trimIfNeeded()
      } catch {
        // 忽略写入失败
      }
    }
  }

  // MARK: - Private helpers

  private func existingFileURL(forKey key: String) -> URL? {
    let jpg = fileURL(forKey: key, ext: "jpg")
    if fileManager.fileExists(atPath: jpg.path) { return jpg }
    let png = fileURL(forKey: key, ext: "png")
    if fileManager.fileExists(atPath: png.path) { return png }
    return nil
  }

  private func fileURL(forKey key: String, ext: String) -> URL {
    let hashed = sha256Hex(of: key)
    return baseURL.appendingPathComponent(hashed).appendingPathExtension(ext)
  }

  private func sha256Hex(of string: String) -> String {
    let data = Data(string.utf8)
    let digest = SHA256.hash(data: data)
    return digest.compactMap { String(format: "%02x", $0) }.joined()
  }

  private func encode(cgImage: CGImage, ext: String) -> Data? {
    let data = NSMutableData()
    let uti: CFString =
      (ext == "png" ? UTType.png.identifier as CFString : UTType.jpeg.identifier as CFString)
    guard let dest = CGImageDestinationCreateWithData(data as CFMutableData, uti, 1, nil) else {
      return nil
    }
    let options: [CFString: Any]
    if ext == "png" {
      options = [:]
    } else {
      options = [kCGImageDestinationLossyCompressionQuality: 0.85]
    }
    CGImageDestinationAddImage(dest, cgImage, options as CFDictionary)
    if CGImageDestinationFinalize(dest) {
      return data as Data
    }
    return nil
  }

  private func currentDiskUsage() -> Int {
    guard
      let files = try? fileManager.contentsOfDirectory(
        at: baseURL, includingPropertiesForKeys: [.fileSizeKey], options: .skipsHiddenFiles)
    else { return 0 }
    var total = 0
    for f in files {
      if let values = try? f.resourceValues(forKeys: [.fileSizeKey]), let size = values.fileSize {
        total += size
      }
    }
    return total
  }

  private func trimIfNeeded() {
    var usage = currentDiskUsage()
    guard usage > byteLimit else { return }
    guard
      var files = try? fileManager.contentsOfDirectory(
        at: baseURL, includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
        options: .skipsHiddenFiles)
    else { return }
    files.sort { (a, b) -> Bool in
      let va =
        (try? a.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
        ?? Date.distantPast
      let vb =
        (try? b.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
        ?? Date.distantPast
      return va < vb
    }
    for f in files {
      let size = (try? f.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
      try? fileManager.removeItem(at: f)
      usage -= size
      if usage <= byteLimit { break }
    }
  }
}

extension NSImage {
  fileprivate func cgImageForCurrentRepresentation() -> CGImage? {
    var rect = CGRect(origin: .zero, size: size)
    return cgImage(forProposedRect: &rect, context: nil, hints: nil)
  }
}
