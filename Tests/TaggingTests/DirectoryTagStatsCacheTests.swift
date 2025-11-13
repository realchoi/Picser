import XCTest
@testable import Picser

final class DirectoryTagStatsCacheTests: XCTestCase {
  var cache: DirectoryTagStatsCache!

  override func setUp() async throws {
    cache = DirectoryTagStatsCache(maxEntries: 10)  // 小容量便于测试
  }

  // MARK: - Basic Functionality Tests

  func testCacheStoreAndRetrieve() async {
    // 测试：存储和检索基本功能
    let counts = [Int64(1): 5, Int64(2): 3]
    await cache.store(counts: counts, for: "/path/to/dir1")

    let retrieved = await cache.cachedCounts(for: "/path/to/dir1")
    XCTAssertEqual(retrieved, counts)
  }

  func testCacheMissReturnsNil() async {
    // 测试：缓存未命中应返回 nil
    let result = await cache.cachedCounts(for: "/nonexistent/path")
    XCTAssertNil(result)
  }

  func testCacheInvalidation() async {
    // 测试：失效单个缓存条目
    let counts = [Int64(1): 10]
    await cache.store(counts: counts, for: "/path/to/dir")

    // 验证缓存存在
    var retrieved = await cache.cachedCounts(for: "/path/to/dir")
    XCTAssertNotNil(retrieved)

    // 失效后应该返回 nil
    await cache.invalidate(directory: "/path/to/dir")
    retrieved = await cache.cachedCounts(for: "/path/to/dir")
    XCTAssertNil(retrieved)
  }

  func testBatchInvalidation() async {
    // 测试：批量失效多个缓存条目
    await cache.store(counts: [1: 1], for: "/dir1")
    await cache.store(counts: [2: 2], for: "/dir2")
    await cache.store(counts: [3: 3], for: "/dir3")

    // 批量失效
    await cache.invalidate(directories: ["/dir1", "/dir3"])

    // 验证结果
    XCTAssertNil(await cache.cachedCounts(for: "/dir1"))
    XCTAssertNotNil(await cache.cachedCounts(for: "/dir2"))
    XCTAssertNil(await cache.cachedCounts(for: "/dir3"))
  }

  func testInvalidateAll() async {
    // 测试：清空所有缓存
    await cache.store(counts: [1: 1], for: "/dir1")
    await cache.store(counts: [2: 2], for: "/dir2")

    await cache.invalidateAll()

    XCTAssertNil(await cache.cachedCounts(for: "/dir1"))
    XCTAssertNil(await cache.cachedCounts(for: "/dir2"))
  }

  // MARK: - LRU Eviction Tests

  func testLRUEviction() async {
    // 测试：LRU 淘汰策略
    // 缓存容量为 10，阈值为 12（120%），因此需要存储 13 个条目才会触发淘汰

    // 存储 13 个条目
    for i in 1...13 {
      await cache.store(counts: [Int64(i): i], for: "/dir\(i)")
    }

    // 验证缓存状态
    let stats = await cache.cacheStats()
    XCTAssertEqual(stats.count, 10, "Cache should be trimmed to maxEntries")

    // 最早的条目（dir1, dir2, dir3）应该被淘汰
    XCTAssertNil(await cache.cachedCounts(for: "/dir1"))
    XCTAssertNil(await cache.cachedCounts(for: "/dir2"))
    XCTAssertNil(await cache.cachedCounts(for: "/dir3"))

    // 最近的条目应该保留
    XCTAssertNotNil(await cache.cachedCounts(for: "/dir10"))
    XCTAssertNotNil(await cache.cachedCounts(for: "/dir11"))
    XCTAssertNotNil(await cache.cachedCounts(for: "/dir12"))
    XCTAssertNotNil(await cache.cachedCounts(for: "/dir13"))
  }

  func testAccessUpdatesLRUOrder() async {
    // 测试：访问操作应该更新 LRU 顺序
    // 存储 12 个条目（超过阈值）
    for i in 1...12 {
      await cache.store(counts: [Int64(i): i], for: "/dir\(i)")
    }

    // 访问 dir1 和 dir2，提升它们的优先级
    _ = await cache.cachedCounts(for: "/dir1")
    _ = await cache.cachedCounts(for: "/dir2")

    // 再存储一个新条目，触发淘汰
    await cache.store(counts: [999: 999], for: "/dir13")

    // dir1 和 dir2 应该因为最近被访问而保留
    XCTAssertNotNil(await cache.cachedCounts(for: "/dir1"))
    XCTAssertNotNil(await cache.cachedCounts(for: "/dir2"))

    // 最早的未访问条目应该被淘汰
    XCTAssertNil(await cache.cachedCounts(for: "/dir3"))
  }

  func testDelayedEviction() async {
    // 测试：延迟淘汰策略（只有超过阈值才触发）
    // 存储 11 个条目（未超过阈值 12）
    for i in 1...11 {
      await cache.store(counts: [Int64(i): i], for: "/dir\(i)")
    }

    let stats = await cache.cacheStats()
    XCTAssertEqual(stats.count, 11, "Should not evict until threshold is reached")

    // 所有条目都应该存在
    for i in 1...11 {
      XCTAssertNotNil(await cache.cachedCounts(for: "/dir\(i)"))
    }

    // 存储第 13 个条目，超过阈值，触发淘汰
    await cache.store(counts: [99: 99], for: "/dir13")

    let statsAfter = await cache.cacheStats()
    XCTAssertEqual(statsAfter.count, 10, "Should trim to maxEntries after exceeding threshold")
  }

  // MARK: - Edge Cases

  func testEmptyCountsStorage() async {
    // 测试：存储空的统计数据
    await cache.store(counts: [:], for: "/empty")
    let retrieved = await cache.cachedCounts(for: "/empty")
    XCTAssertNotNil(retrieved)
    XCTAssertEqual(retrieved?.count, 0)
  }

  func testSameDirectoryUpdate() async {
    // 测试：更新同一目录的数据
    await cache.store(counts: [1: 10], for: "/dir")
    await cache.store(counts: [2: 20], for: "/dir")

    let retrieved = await cache.cachedCounts(for: "/dir")
    XCTAssertEqual(retrieved, [2: 20], "Should update with latest data")
  }

  func testSequenceNumberIncrement() async {
    // 测试：访问序列号正确递增
    let stats1 = await cache.cacheStats()
    XCTAssertEqual(stats1.sequence, 0)

    await cache.store(counts: [1: 1], for: "/dir1")
    let stats2 = await cache.cacheStats()
    XCTAssertEqual(stats2.sequence, 1)

    _ = await cache.cachedCounts(for: "/dir1")
    let stats3 = await cache.cacheStats()
    XCTAssertEqual(stats3.sequence, 2)

    await cache.store(counts: [2: 2], for: "/dir2")
    let stats4 = await cache.cacheStats()
    XCTAssertEqual(stats4.sequence, 3)
  }

  // MARK: - Performance Tests

  func testLargeScalePerformance() async {
    // 测试：大规模缓存操作的性能
    let largeCache = DirectoryTagStatsCache(maxEntries: 200)

    // 存储 250 个条目（超过阈值 240）
    measure {
      Task {
        for i in 1...250 {
          await largeCache.store(counts: [Int64(i): i * 2], for: "/dir\(i)")
        }
      }
    }

    // 验证最终状态
    Task {
      let stats = await largeCache.cacheStats()
      XCTAssertEqual(stats.count, 200)
    }
  }

  func testConcurrentAccess() async {
    // 测试：并发访问的正确性
    // Actor 隔离应该确保线程安全
    await withTaskGroup(of: Void.self) { group in
      // 并发存储
      for i in 1...20 {
        group.addTask {
          await self.cache.store(counts: [Int64(i): i], for: "/dir\(i)")
        }
      }

      // 并发访问
      for i in 1...20 {
        group.addTask {
          _ = await self.cache.cachedCounts(for: "/dir\(i)")
        }
      }
    }

    // 验证缓存状态一致
    let stats = await cache.cacheStats()
    XCTAssertGreaterThan(stats.count, 0)
    XCTAssertLessThanOrEqual(stats.count, 20)
  }
}
