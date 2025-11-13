import XCTest
@testable import Picser

final class ColorHexTests: XCTestCase {
  func testNormalizedHexAcceptsValidLength() {
    XCTAssertEqual("#abc123".normalizedHexColor(), "#ABC123")
    XCTAssertEqual("FF00FFAA".normalizedHexColor(), "#FF00FFAA")
  }

  func testNormalizedHexRejectsInvalidInput() {
    XCTAssertNil("#12".normalizedHexColor())
    XCTAssertNil("GHIJKL".normalizedHexColor())
    XCTAssertNil("#12345Z".normalizedHexColor())
    XCTAssertNil("".normalizedHexColor())
  }
}
