//
//  DirectoryTagStatsCache.swift
//
//  Created by Eric Cai on 2025/11/10.
//

import Foundation

/// 基于 LRU (Least Recently Used) 策略的目录标签统计缓存
///
/// 使用访问序列号来跟踪访问顺序，避免浮点数比较的精度问题。
/// 采用延迟淘汰策略，只在超过容量上限时才执行清理，提高性能。
///
/// 时间复杂度：
/// - cachedCounts: O(1)
/// - store: 摊销 O(1)，淘汰时 O(n) 其中 n = maxEntries
/// - invalidate: O(1)
///
/// 线程安全：使用 actor 隔离确保并发安全
actor DirectoryTagStatsCache {
  /// 缓存条目，包含统计数据和访问序列号
  private struct Entry {
    /// 标签 ID 到使用次数的映射
    var counts: [Int64: Int]
    /// 访问序列号，用于 LRU 淘汰策略
    var accessSequence: UInt64
  }

  /// 主存储：目录路径 -> 缓存条目
  private var storage: [String: Entry] = [:]

  /// 最大缓存条目数
  private let maxEntries: Int

  /// 触发清理的阈值（maxEntries 的 120%）
  /// 延迟清理避免频繁触发淘汰逻辑
  private let cleanupThreshold: Int

  /// 全局访问序列号，单调递增
  /// 使用 UInt64 避免溢出（需要访问 2^64 次才溢出）
  private var currentSequence: UInt64 = 0

  /// 初始化缓存
  /// - Parameter maxEntries: 最大缓存条目数，默认 200
  init(maxEntries: Int = 200) {
    self.maxEntries = maxEntries
    // 设置清理阈值为 maxEntries 的 120%，避免频繁清理
    self.cleanupThreshold = maxEntries + (maxEntries / 5)
  }

  /// 获取目录的缓存统计数据
  ///
  /// - Parameter directory: 目录路径
  /// - Returns: 标签统计数据，如果缓存未命中则返回 nil
  func cachedCounts(for directory: String) -> [Int64: Int]? {
    guard var entry = storage[directory] else { return nil }

    // 更新访问序列号（LRU 策略核心）
    currentSequence &+= 1  // 使用溢出加法，虽然 UInt64 实际不会溢出
    entry.accessSequence = currentSequence
    storage[directory] = entry

    return entry.counts
  }

  /// 存储目录的统计数据到缓存
  ///
  /// - Parameters:
  ///   - counts: 标签统计数据
  ///   - directory: 目录路径
  func store(counts: [Int64: Int], for directory: String) {
    currentSequence &+= 1
    storage[directory] = Entry(counts: counts, accessSequence: currentSequence)

    // 延迟清理：只有超过阈值时才执行
    if storage.count > cleanupThreshold {
      trimToCapacity()
    }
  }

  /// 失效指定目录的缓存
  ///
  /// - Parameter directory: 要失效的目录路径
  func invalidate(directory: String) {
    storage.removeValue(forKey: directory)
  }

  /// 批量失效多个目录的缓存
  ///
  /// - Parameter directories: 要失效的目录路径集合
  func invalidate(directories: Set<String>) {
    for directory in directories {
      storage.removeValue(forKey: directory)
    }
  }

  /// 清空所有缓存
  func invalidateAll() {
    storage.removeAll()
  }

  /// 将缓存裁剪到容量限制内
  ///
  /// 算法：使用部分排序找到访问序列号最小的条目并移除
  /// 时间复杂度：O(n log k)，其中 k 是要移除的条目数
  private func trimToCapacity() {
    let overflow = storage.count - maxEntries
    guard overflow > 0 else { return }

    // 使用 sorted 的 prefix 方法，Swift 会自动优化为部分排序
    // 找到访问序列号最小的 overflow 个条目
    let keysToRemove = storage
      .sorted { lhs, rhs in
        lhs.value.accessSequence < rhs.value.accessSequence
      }
      .prefix(overflow)
      .map(\.key)

    // 移除过期条目
    for key in keysToRemove {
      storage.removeValue(forKey: key)
    }
  }

  // MARK: - Debug & Monitoring

  /// 获取当前缓存状态（用于调试和监控）
  func cacheStats() -> (count: Int, maxEntries: Int, sequence: UInt64) {
    return (storage.count, maxEntries, currentSequence)
  }
}
