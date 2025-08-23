// PicTube/Models/DiskCache.swift

import AppKit
import CryptoKit
import Foundation

/// 升级后的磁盘缓存，现在存储和加载二进制的 `MetadataCache` 对象。
actor DiskCache {
  static let shared = DiskCache()

  private let baseURL: URL
  private let fileManager = FileManager.default
  private var byteLimit: Int = 500 * 1024 * 1024  // 默认 500MB，因为元数据缓存通常更小

  // 使用 Codable 来序列化和反序列化我们的缓存结构体
  private let encoder = JSONEncoder()
  private let decoder = JSONDecoder()

  private init() {
    // 将缓存目录更改为 "MetadataCache" 以避免与旧缓存冲突
    let caches = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first!
    let dir = caches.appendingPathComponent("PicTube/MetadataCache", isDirectory: true)
    if !fileManager.fileExists(atPath: dir.path) {
      try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
    }
    baseURL = dir

    // 虽然我们不直接用它来编码，但预热一下总是好的
    encoder.outputFormatting = .prettyPrinted
  }

  /// 返回磁盘缓存目录
  func cacheDirectoryURL() -> URL { baseURL }

  func setByteLimit(_ bytes: Int) {
    byteLimit = max(64 * 1024 * 1024, bytes)
  }

  // MARK: - 新的核心方法：存储和加载 MetadataCache

  /// 将一个 MetadataCache 对象序列化为二进制数据并存入磁盘
  /// - Parameters:
  ///   - metadata: 要存储的元数据缓存对象。
  ///   - key: 用于生成文件名的唯一键（通常是原始图片文件的路径）。
  func store(metadata: MetadataCache, forKey key: String) {
    let fileURL = self.fileURL(forKey: key)
    do {
      // 1. 使用 Codable 将结构体编码成 Data (二进制数据)
      let data = try encoder.encode(metadata)
      // 2. 将数据写入文件
      try data.write(to: fileURL, options: .atomic)
      trimIfNeeded()  // 检查是否需要清理旧缓存
    } catch {
      print("Failed to store metadata cache for key \(key): \(error)")
    }
  }

  /// 从磁盘读取二进制文件，并将其反序列化回 MetadataCache 对象
  /// - Parameter key: 用于查找缓存文件的唯一键。
  /// - Returns: 如果缓存存在且有效，则返回 MetadataCache 对象，否则返回 nil。
  func retrieve(forKey key: String) -> MetadataCache? {
    let fileURL = self.fileURL(forKey: key)
    guard fileManager.fileExists(atPath: fileURL.path) else {
      return nil
    }

    do {
      // 1. 从文件读取二进制数据
      let data = try Data(contentsOf: fileURL)
      // 2. 使用 Codable 将数据解码回我们的结构体
      let metadata = try decoder.decode(MetadataCache.self, from: data)

      // 3. 验证缓存的有效性
      guard metadata.magicNumber == 0x5049_4354,  // 检查魔数
        let attributes = try? fileManager.attributesOfItem(atPath: key),  // 注意：这里的 key 是原始文件路径
        let modificationDate = attributes[.modificationDate] as? Date,
        // 检查时间戳是否匹配，确保原始文件未被修改
        abs(modificationDate.timeIntervalSince1970 - metadata.originalFileTimestamp) < 1
      else {
        // 缓存无效（文件被修改或格式错误），删除它
        try? fileManager.removeItem(at: fileURL)
        return nil
      }

      // 更新文件的访问日期，用于 LRU (最近最少使用) 清理策略
      try? fileManager.setAttributes([.modificationDate: Date()], ofItemAtPath: fileURL.path)

      return metadata
    } catch {
      // 解码失败或文件读取失败，删除损坏的缓存文件
      try? fileManager.removeItem(at: fileURL)
      return nil
    }
  }

  // MARK: - 缓存管理 (基本保持不变)

  /// 获取缓存目录总大小（字节）
  func getCacheSize() -> Int64 {
    guard
      let files = try? fileManager.contentsOfDirectory(
        at: baseURL, includingPropertiesForKeys: [.fileSizeKey], options: .skipsHiddenFiles)
    else { return 0 }

    return files.reduce(0) { total, url in
      let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
      return total + Int64(size)
    }
  }

  /// 清空所有缓存文件
  func clearCache() async throws {
    let files = try fileManager.contentsOfDirectory(
      at: baseURL, includingPropertiesForKeys: [], options: .skipsHiddenFiles)
    for file in files {
      try fileManager.removeItem(at: file)
    }
  }

  /// 格式化文件大小显示
  func formatFileSize(_ bytes: Int64) -> String {
    let formatter = ByteCountFormatter()
    formatter.allowedUnits = [.useKB, .useMB, .useGB]
    formatter.countStyle = .file
    return formatter.string(fromByteCount: bytes)
  }

  // MARK: - 私有辅助方法 (有修改)

  /// 为缓存文件生成一个唯一的、无后缀名的 URL
  private func fileURL(forKey key: String) -> URL {
    // 使用 SHA256 对 key (原始文件路径)进行哈希，生成一个固定长度的文件名
    let hashed = sha256Hex(of: key)
    return baseURL.appendingPathComponent(hashed)  // 没有后缀名
  }

  private func sha256Hex(of string: String) -> String {
    let data = Data(string.utf8)
    let digest = SHA256.hash(data: data)
    return digest.compactMap { String(format: "%02x", $0) }.joined()
  }

  private func currentDiskUsage() -> Int {
    guard
      let files = try? fileManager.contentsOfDirectory(
        at: baseURL, includingPropertiesForKeys: [.fileSizeKey], options: .skipsHiddenFiles)
    else { return 0 }
    return files.reduce(0) { total, url in
      total + ((try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
    }
  }

  /// LRU 缓存清理逻辑
  private func trimIfNeeded() {
    var usage = currentDiskUsage()
    guard usage > byteLimit else { return }

    guard
      var files = try? fileManager.contentsOfDirectory(
        at: baseURL,
        includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
        options: .skipsHiddenFiles
      )
    else { return }

    // 按修改日期排序，最早的排在前面
    files.sort {
      let dateA =
        (try? $0.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        ?? .distantPast
      let dateB =
        (try? $1.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        ?? .distantPast
      return dateA < dateB
    }

    for file in files {
      if let size = (try? file.resourceValues(forKeys: [.fileSizeKey]))?.fileSize {
        try? fileManager.removeItem(at: file)
        usage -= size
        if usage <= byteLimit { break }
      }
    }
  }
}
