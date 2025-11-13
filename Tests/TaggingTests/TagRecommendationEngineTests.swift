import XCTest
@testable import Picser

final class TagRecommendationEngineTests: XCTestCase {
  func testDirectoryStatsInfluenceRecommendations() {
    let engine = TagRecommendationEngine()
    let primary = URL(fileURLWithPath: "/tmp/photos/a.jpg")
    let neighbor = primary.deletingLastPathComponent().appendingPathComponent("b.jpg")

    let assignments: [String: [TagRecord]] = [
      neighbor.path: [
        TagRecord(id: 2, name: "City", colorHex: "#FF0000", usageCount: 0, createdAt: .now, updatedAt: .now)
      ]
    ]
    let scoped = [
      ScopedTagSummary(id: 3, name: "Travel", colorHex: nil, usageCount: 5)
    ]
    let all = [
      TagRecord(id: 2, name: "City", colorHex: "#FF0000", usageCount: 10, createdAt: .now, updatedAt: .now),
      TagRecord(id: 3, name: "Travel", colorHex: nil, usageCount: 8, createdAt: .now, updatedAt: .now),
      TagRecord(id: 4, name: "Family", colorHex: nil, usageCount: 3, createdAt: .now, updatedAt: .now)
    ]
    let directoryStats: [Int64: Int] = [
      4: 6
    ]

    let result = engine.recommendedTags(
      for: primary,
      assignments: assignments,
      scopedTags: scoped,
      allTags: all,
      directoryStats: directoryStats,
      limit: 3
    )

    XCTAssertEqual(result.map(\.id), [2, 3, 4], "同目录权重应优先，其次参考作用域与目录热度")
  }

  func testFallbackUsesGlobalListWhenNoScores() {
    let engine = TagRecommendationEngine()
    let primary = URL(fileURLWithPath: "/tmp/photos/a.jpg")
    let all = [
      TagRecord(id: 1, name: "Alpha", colorHex: nil, usageCount: 3, createdAt: .now, updatedAt: .now),
      TagRecord(id: 2, name: "Beta", colorHex: nil, usageCount: 5, createdAt: .now, updatedAt: .now)
    ]

    let result = engine.recommendedTags(
      for: primary,
      assignments: [:],
      scopedTags: [],
      allTags: all,
      directoryStats: [:],
      limit: 4
    )

    XCTAssertEqual(result.map(\.id), [1, 2], "在缺少上下文时应按名称稳定排序")
  }
}
