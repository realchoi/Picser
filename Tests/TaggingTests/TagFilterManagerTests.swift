import XCTest
@testable import Picser

final class TagFilterManagerTests: XCTestCase {
  func testKeywordColorAndModeFiltering() async {
    let manager = TagFilterManager()
    let url = URL(fileURLWithPath: "/tmp/photos/flower.jpg")
    let assignments: [String: [TagRecord]] = [
      url.path: [
        TagRecord(id: 1, name: "Flower", colorHex: "#FF00FF", usageCount: 0, createdAt: .now, updatedAt: .now)
      ]
    ]
    let filter = TagFilter(mode: .all, tagIDs: [1], keyword: "flower", colorHexes: ["#ff00ff"])

    let result = await manager.filteredImageURLs(
      filter: filter,
      urls: [url],
      assignments: assignments,
      assignmentsVersion: 1
    )

    XCTAssertEqual(result, [url])
  }

  func testExcludeModeRemovesTaggedImages() async {
    let manager = TagFilterManager()
    let url = URL(fileURLWithPath: "/tmp/photos/car.jpg")
    let assignments: [String: [TagRecord]] = [
      url.path: [
        TagRecord(id: 9, name: "Vehicle", colorHex: nil, usageCount: 0, createdAt: .now, updatedAt: .now)
      ]
    ]
    let filter = TagFilter(mode: .exclude, tagIDs: [9])

    let result = await manager.filteredImageURLs(
      filter: filter,
      urls: [url],
      assignments: assignments,
      assignmentsVersion: 2
    )

    XCTAssertTrue(result.isEmpty)
  }
}
