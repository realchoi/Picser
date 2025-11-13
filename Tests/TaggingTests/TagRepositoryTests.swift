import XCTest
@testable import Picser

final class TagRepositoryTests: XCTestCase {
  var databaseURL: URL!
  var database: TaggingDatabase!
  var repository: TagRepository!

  override func setUpWithError() throws {
    databaseURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("TagRepositoryTests-\(UUID().uuidString).sqlite3")
    database = TaggingDatabase(databaseURL: databaseURL)
    repository = TagRepository(database: database)
  }

  override func tearDownWithError() throws {
    if let databaseURL {
      try? FileManager.default.removeItem(at: databaseURL)
    }
  }

  func testAssignAndFetchAllTags() async throws {
    let image = URL(fileURLWithPath: "/tmp/repo-tests/photo-1.jpg")
    let created = try await repository.assign(tagNames: ["Travel"], to: image)
    XCTAssertEqual(created.first?.name, "Travel")

    let allTags = try await repository.fetchAllTags()
    XCTAssertEqual(allTags.count, 1)
    XCTAssertEqual(allTags.first?.name, "Travel")
  }

  func testMergeTagsCreatesSingleTarget() async throws {
    let url = URL(fileURLWithPath: "/tmp/repo-tests/photo-2.jpg")
    _ = try await repository.assign(tagNames: ["A", "B"], to: [url])
    let fetched = try await repository.fetchAllTags()
    XCTAssertEqual(Set(fetched.map(\.name)), ["A", "B"])

    let mergedTarget = try await repository.mergeTags(sourceIDs: fetched.map(\.id), targetName: "Unified")
    XCTAssertGreaterThan(mergedTarget, 0)

    let refreshed = try await repository.fetchAllTags()
    XCTAssertEqual(refreshed.count, 1)
    XCTAssertEqual(refreshed.first?.name, "Unified")
  }

  // MARK: - Error Handling Tests

  func testBulkAssignHandlesDatabaseErrors() async throws {
    // 测试：批量分配应该正确处理数据库错误
    let url = URL(fileURLWithPath: "/tmp/repo-tests/photo-bulk.jpg")

    // 正常情况：应该成功
    let tags = try await repository.assign(tagNames: ["Test1", "Test2", "Test3"], to: url)
    XCTAssertEqual(tags.count, 3)

    // 验证所有标签都被正确分配
    let fetched = try await repository.fetchTags(forImageAt: url.standardizedFileURL.path)
    XCTAssertEqual(fetched.count, 3)
    XCTAssertEqual(Set(fetched.map(\.name)), ["Test1", "Test2", "Test3"])
  }

  func testMergeTagsWithValidData() async throws {
    // 测试：合并标签应该正确删除源标签并保留目标标签
    let url1 = URL(fileURLWithPath: "/tmp/repo-tests/photo-merge-1.jpg")
    let url2 = URL(fileURLWithPath: "/tmp/repo-tests/photo-merge-2.jpg")

    // 创建两个标签，分别分配给两张图片
    _ = try await repository.assign(tagNames: ["Source1"], to: url1)
    _ = try await repository.assign(tagNames: ["Source2"], to: url2)

    let beforeMerge = try await repository.fetchAllTags()
    XCTAssertEqual(beforeMerge.count, 2)

    // 合并标签
    let sourceIDs = beforeMerge.map(\.id)
    let targetID = try await repository.mergeTags(sourceIDs: sourceIDs, targetName: "Merged")
    XCTAssertGreaterThan(targetID, 0)

    // 验证：只剩一个标签
    let afterMerge = try await repository.fetchAllTags()
    XCTAssertEqual(afterMerge.count, 1)
    XCTAssertEqual(afterMerge.first?.name, "Merged")

    // 验证：两张图片都应该有新标签
    let tags1 = try await repository.fetchTags(forImageAt: url1.standardizedFileURL.path)
    let tags2 = try await repository.fetchTags(forImageAt: url2.standardizedFileURL.path)
    XCTAssertEqual(tags1.count, 1)
    XCTAssertEqual(tags2.count, 1)
    XCTAssertEqual(tags1.first?.name, "Merged")
    XCTAssertEqual(tags2.first?.name, "Merged")
  }

  func testAssignDuplicateTagsDoesNotFail() async throws {
    // 测试：重复分配相同标签不应该失败
    let url = URL(fileURLWithPath: "/tmp/repo-tests/photo-dup.jpg")

    // 第一次分配
    let tags1 = try await repository.assign(tagNames: ["Duplicate"], to: url)
    XCTAssertEqual(tags1.count, 1)

    // 第二次分配相同标签（INSERT OR IGNORE 应该处理）
    let tags2 = try await repository.assign(tagNames: ["Duplicate"], to: url)
    XCTAssertEqual(tags2.count, 1)

    // 验证：仍然只有一个标签关联
    let fetched = try await repository.fetchTags(forImageAt: url.standardizedFileURL.path)
    XCTAssertEqual(fetched.count, 1)
  }
}
