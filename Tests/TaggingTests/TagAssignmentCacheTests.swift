import XCTest
@testable import Picser

@MainActor
final class TagAssignmentCacheTests: XCTestCase {
  var cache: TagAssignmentCache!

  override func setUp() {
    cache = TagAssignmentCache()
  }

  // MARK: - Correctness Tests

  func testRebuildScopedCountsCorrectness() {
    // 测试：重建作用域计数应该正确统计标签使用次数
    let tag1 = TagRecord(id: 1, name: "Tag1", colorHex: "#FF0000", usageCount: 0, createdAt: Date(), updatedAt: Date())
    let tag2 = TagRecord(id: 2, name: "Tag2", colorHex: "#00FF00", usageCount: 0, createdAt: Date(), updatedAt: Date())
    let tag3 = TagRecord(id: 3, name: "Tag3", colorHex: "#0000FF", usageCount: 0, createdAt: Date(), updatedAt: Date())

    // 创建测试数据：3 张图片，每张有不同的标签组合
    let assignments: [String: [TagRecord]] = [
      "/path/to/image1.jpg": [tag1, tag2],      // Tag1, Tag2
      "/path/to/image2.jpg": [tag1, tag3],      // Tag1, Tag3
      "/path/to/image3.jpg": [tag1, tag2, tag3] // Tag1, Tag2, Tag3
    ]

    cache.replaceAll(with: assignments)

    let urls = [
      URL(fileURLWithPath: "/path/to/image1.jpg"),
      URL(fileURLWithPath: "/path/to/image2.jpg"),
      URL(fileURLWithPath: "/path/to/image3.jpg")
    ]
    cache.syncScopedPaths(with: urls)

    // 验证：scopedTags 应该包含 3 个标签
    XCTAssertEqual(cache.scopedTags.count, 3)

    // 验证：Tag1 出现 3 次，Tag2 出现 2 次，Tag3 出现 2 次
    let tag1Summary = cache.scopedTags.first { $0.id == 1 }
    let tag2Summary = cache.scopedTags.first { $0.id == 2 }
    let tag3Summary = cache.scopedTags.first { $0.id == 3 }

    XCTAssertEqual(tag1Summary?.usageCount, 3, "Tag1 should be used 3 times")
    XCTAssertEqual(tag2Summary?.usageCount, 2, "Tag2 should be used 2 times")
    XCTAssertEqual(tag3Summary?.usageCount, 2, "Tag3 should be used 2 times")

    // 验证：标签名称和颜色正确
    XCTAssertEqual(tag1Summary?.name, "Tag1")
    XCTAssertEqual(tag1Summary?.colorHex, "#FF0000")
    XCTAssertEqual(tag2Summary?.name, "Tag2")
    XCTAssertEqual(tag2Summary?.colorHex, "#00FF00")
    XCTAssertEqual(tag3Summary?.name, "Tag3")
    XCTAssertEqual(tag3Summary?.colorHex, "#0000FF")
  }

  func testUpdateAssignmentsIncrementalUpdate() {
    // 测试：增量更新应该只影响变化的路径
    let tag1 = TagRecord(id: 1, name: "Original", colorHex: "#FF0000", usageCount: 0, createdAt: Date(), updatedAt: Date())
    let tag2 = TagRecord(id: 2, name: "Updated", colorHex: "#00FF00", usageCount: 0, createdAt: Date(), updatedAt: Date())

    // 初始状态
    cache.replaceAll(with: ["/path/to/image1.jpg": [tag1]])

    // 增量更新
    cache.updateAssignments(["/path/to/image2.jpg": [tag2]])

    // 验证：两个路径都应该存在
    XCTAssertEqual(cache.assignments.count, 2)
    XCTAssertEqual(cache.assignments["/path/to/image1.jpg"], [tag1])
    XCTAssertEqual(cache.assignments["/path/to/image2.jpg"], [tag2])
  }

  func testEmptyAssignmentRemovesPath() {
    // 测试：空数组应该从缓存中移除路径
    let tag1 = TagRecord(id: 1, name: "Tag1", colorHex: "#FF0000", usageCount: 0, createdAt: Date(), updatedAt: Date())

    cache.replaceAll(with: ["/path/to/image1.jpg": [tag1]])
    XCTAssertEqual(cache.assignments.count, 1)

    // 更新为空数组
    cache.updateAssignments(["/path/to/image1.jpg": []])

    // 验证：路径应该被移除
    XCTAssertEqual(cache.assignments.count, 0)
    XCTAssertNil(cache.assignments["/path/to/image1.jpg"])
  }

  // MARK: - Performance Tests

  func testRebuildScopedCountsPerformance() {
    // 测试：重建作用域计数在大数据集下的性能
    let tags = (1...20).map { id in
      TagRecord(
        id: Int64(id),
        name: "Tag\(id)",
        colorHex: "#\(String(format: "%06X", id * 100000))",
        usageCount: 0,
        createdAt: Date(),
        updatedAt: Date()
      )
    }

    // 创建 1000 张图片的测试数据，每张图片随机分配 3-7 个标签
    var assignments: [String: [TagRecord]] = [:]
    for i in 1...1000 {
      let tagCount = Int.random(in: 3...7)
      let randomTags = (0..<tagCount).map { _ in tags.randomElement()! }
      assignments["/path/to/image\(i).jpg"] = randomTags
    }

    cache.replaceAll(with: assignments)

    let urls = (1...1000).map { URL(fileURLWithPath: "/path/to/image\($0).jpg") }

    // 测量性能：应该在 100ms 内完成
    measure {
      cache.syncScopedPaths(with: urls)
    }

    // 验证：结果正确
    XCTAssertGreaterThan(cache.scopedTags.count, 0)
    XCTAssertLessThanOrEqual(cache.scopedTags.count, 20)
  }

  func testUpdateAssignmentsPerformance() {
    // 测试：增量更新在大数据集下的性能
    let tag = TagRecord(id: 1, name: "Tag1", colorHex: "#FF0000", usageCount: 0, createdAt: Date(), updatedAt: Date())

    var initialAssignments: [String: [TagRecord]] = [:]
    for i in 1...1000 {
      initialAssignments["/path/to/image\(i).jpg"] = [tag]
    }
    cache.replaceAll(with: initialAssignments)

    // 准备 100 个更新
    let updates = (1...100).reduce(into: [String: [TagRecord]]()) { result, i in
      result["/path/to/image\(i).jpg"] = []
    }

    // 测量性能：应该在 50ms 内完成
    measure {
      cache.updateAssignments(updates)
    }
  }

  // MARK: - Edge Cases

  func testSyncScopedPathsWithEmptyArray() {
    // 测试：同步空路径数组应该清空作用域
    let tag = TagRecord(id: 1, name: "Tag1", colorHex: "#FF0000", usageCount: 0, createdAt: Date(), updatedAt: Date())
    cache.replaceAll(with: ["/path/to/image1.jpg": [tag]])

    cache.syncScopedPaths(with: [URL(fileURLWithPath: "/path/to/image1.jpg")])
    XCTAssertEqual(cache.scopedTags.count, 1)

    cache.syncScopedPaths(with: [])
    XCTAssertEqual(cache.scopedTags.count, 0)
  }

  func testTagsForURLReturnsCorrectTags() {
    // 测试：根据 URL 获取标签应该返回正确结果
    let tag1 = TagRecord(id: 1, name: "Tag1", colorHex: "#FF0000", usageCount: 0, createdAt: Date(), updatedAt: Date())
    let tag2 = TagRecord(id: 2, name: "Tag2", colorHex: "#00FF00", usageCount: 0, createdAt: Date(), updatedAt: Date())

    cache.replaceAll(with: [
      "/path/to/image1.jpg": [tag1],
      "/path/to/image2.jpg": [tag2]
    ])

    let url1 = URL(fileURLWithPath: "/path/to/image1.jpg")
    let url2 = URL(fileURLWithPath: "/path/to/image2.jpg")
    let url3 = URL(fileURLWithPath: "/path/to/image3.jpg") // 不存在

    XCTAssertEqual(cache.tags(for: url1), [tag1])
    XCTAssertEqual(cache.tags(for: url2), [tag2])
    XCTAssertEqual(cache.tags(for: url3), [])
  }
}
