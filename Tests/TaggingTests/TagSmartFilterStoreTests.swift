import XCTest
@testable import Picser

@MainActor
final class TagSmartFilterStoreTests: XCTestCase {
  var store: TagSmartFilterStore!
  let testStorageKey = "test.smartFilters.\(UUID().uuidString)"

  override func setUp() {
    // 使用唯一的存储键避免测试间干扰
    store = TagSmartFilterStore(storageKey: testStorageKey)
  }

  override func tearDown() {
    // 清理测试数据
    UserDefaults.standard.removeObject(forKey: testStorageKey)
  }

  // MARK: - Basic Save and Load Tests

  func testSaveAndLoadFilter() throws {
    // 测试：保存筛选器并重新加载
    let filter = TagFilter(mode: .any, tagIDs: [1, 2, 3], keyword: "test")
    try store.save(filter: filter, named: "Test Filter")

    XCTAssertEqual(store.filters.count, 1)
    XCTAssertEqual(store.filters.first?.name, "Test Filter")
    XCTAssertEqual(store.filters.first?.filter, filter)

    // 重新创建 store，验证持久化
    let newStore = TagSmartFilterStore(storageKey: testStorageKey)
    XCTAssertEqual(newStore.filters.count, 1)
    XCTAssertEqual(newStore.filters.first?.name, "Test Filter")
    XCTAssertEqual(newStore.filters.first?.filter, filter)
  }

  func testSaveEmptyNameDoesNothing() throws {
    // 测试：空名称不应该保存
    let filter = TagFilter(mode: .any, tagIDs: [1])
    try store.save(filter: filter, named: "")

    XCTAssertEqual(store.filters.count, 0)
  }

  func testSaveWhitespaceOnlyNameDoesNothing() throws {
    // 测试：仅空格的名称不应该保存
    let filter = TagFilter(mode: .any, tagIDs: [1])
    try store.save(filter: filter, named: "   \t\n  ")

    XCTAssertEqual(store.filters.count, 0)
  }

  // MARK: - Duplicate Detection Tests

  func testDuplicateNameThrowsError() throws {
    // 测试：重复名称应该抛出错误
    let filter1 = TagFilter(mode: .any, tagIDs: [1])
    let filter2 = TagFilter(mode: .all, tagIDs: [2])

    try store.save(filter: filter1, named: "Duplicate")

    XCTAssertThrowsError(try store.save(filter: filter2, named: "Duplicate")) { error in
      XCTAssertTrue(error is SmartFilterStoreError)
      if let storeError = error as? SmartFilterStoreError {
        XCTAssertEqual(storeError, .duplicateName)
      }
    }
  }

  func testDuplicateNameCaseInsensitive() throws {
    // 测试：名称重复检测应该不区分大小写
    let filter1 = TagFilter(mode: .any, tagIDs: [1])
    let filter2 = TagFilter(mode: .all, tagIDs: [2])

    try store.save(filter: filter1, named: "MyFilter")

    XCTAssertThrowsError(try store.save(filter: filter2, named: "myfilter")) { error in
      XCTAssertTrue(error is SmartFilterStoreError)
    }

    XCTAssertThrowsError(try store.save(filter: filter2, named: "MYFILTER")) { error in
      XCTAssertTrue(error is SmartFilterStoreError)
    }
  }

  func testDuplicateFilterThrowsError() throws {
    // 测试：相同筛选器配置应该抛出错误
    let filter = TagFilter(mode: .any, tagIDs: [1, 2, 3])

    try store.save(filter: filter, named: "First")

    XCTAssertThrowsError(try store.save(filter: filter, named: "Second")) { error in
      XCTAssertTrue(error is SmartFilterStoreError)
      if let storeError = error as? SmartFilterStoreError {
        XCTAssertEqual(storeError, .duplicateFilter)
      }
    }

    // 只应该保存了第一个
    XCTAssertEqual(store.filters.count, 1)
    XCTAssertEqual(store.filters.first?.name, "First")
  }

  // MARK: - Delete Tests

  func testDeleteFilter() throws {
    // 测试：删除筛选器
    let filter1 = TagFilter(mode: .any, tagIDs: [1])
    let filter2 = TagFilter(mode: .all, tagIDs: [2])

    try store.save(filter: filter1, named: "Filter 1")
    try store.save(filter: filter2, named: "Filter 2")

    XCTAssertEqual(store.filters.count, 2)

    let idToDelete = store.filters.first!.id
    store.delete(id: idToDelete)

    XCTAssertEqual(store.filters.count, 1)
    XCTAssertNil(store.filters.first(where: { $0.id == idToDelete }))

    // 验证持久化
    let newStore = TagSmartFilterStore(storageKey: testStorageKey)
    XCTAssertEqual(newStore.filters.count, 1)
  }

  func testDeleteNonexistentFilterDoesNothing() {
    // 测试：删除不存在的筛选器不应该报错
    let randomID = UUID()
    store.delete(id: randomID)
    XCTAssertEqual(store.filters.count, 0)
  }

  // MARK: - Rename Tests

  func testRenameFilter() throws {
    // 测试：重命名筛选器
    let filter = TagFilter(mode: .any, tagIDs: [1])
    try store.save(filter: filter, named: "Old Name")

    let filterID = store.filters.first!.id
    try store.rename(id: filterID, to: "New Name")

    XCTAssertEqual(store.filters.first?.name, "New Name")

    // 验证持久化
    let newStore = TagSmartFilterStore(storageKey: testStorageKey)
    XCTAssertEqual(newStore.filters.first?.name, "New Name")
  }

  func testRenameToEmptyNameDoesNothing() throws {
    // 测试：重命名为空名称不应该生效
    let filter = TagFilter(mode: .any, tagIDs: [1])
    try store.save(filter: filter, named: "Original")

    let filterID = store.filters.first!.id
    try store.rename(id: filterID, to: "")

    XCTAssertEqual(store.filters.first?.name, "Original")
  }

  func testRenameToDuplicateNameThrowsError() throws {
    // 测试：重命名为已存在的名称应该抛出错误
    let filter1 = TagFilter(mode: .any, tagIDs: [1])
    let filter2 = TagFilter(mode: .all, tagIDs: [2])

    try store.save(filter: filter1, named: "Name 1")
    try store.save(filter: filter2, named: "Name 2")

    let filter1ID = store.filters.first { $0.name == "Name 1" }!.id

    XCTAssertThrowsError(try store.rename(id: filter1ID, to: "Name 2")) { error in
      XCTAssertTrue(error is SmartFilterStoreError)
      if let storeError = error as? SmartFilterStoreError {
        XCTAssertEqual(storeError, .duplicateName)
      }
    }

    // 原名称应该保持不变
    XCTAssertEqual(store.filters.first { $0.id == filter1ID }?.name, "Name 1")
  }

  func testRenameToSameNameAllowed() throws {
    // 测试：重命名为自己的名称（大小写不同）应该允许
    let filter = TagFilter(mode: .any, tagIDs: [1])
    try store.save(filter: filter, named: "MyFilter")

    let filterID = store.filters.first!.id
    try store.rename(id: filterID, to: "myfilter")

    XCTAssertEqual(store.filters.first?.name, "myfilter")
  }

  // MARK: - Reorder Tests

  func testReorderFilters() throws {
    // 测试：重新排序筛选器
    let filter1 = TagFilter(mode: .any, tagIDs: [1])
    let filter2 = TagFilter(mode: .any, tagIDs: [2])
    let filter3 = TagFilter(mode: .any, tagIDs: [3])

    try store.save(filter: filter1, named: "Filter 1")
    try store.save(filter: filter2, named: "Filter 2")
    try store.save(filter: filter3, named: "Filter 3")

    // 当前顺序：Filter 3, Filter 2, Filter 1（新保存的在前）
    XCTAssertEqual(store.filters.map(\.name), ["Filter 3", "Filter 2", "Filter 1"])

    // 移动索引 0（Filter 3）到索引 2
    store.reorder(from: IndexSet([0]), to: 2)

    // 新顺序应该是：Filter 2, Filter 1, Filter 3
    XCTAssertEqual(store.filters.map(\.name), ["Filter 2", "Filter 1", "Filter 3"])

    // 验证持久化
    let newStore = TagSmartFilterStore(storageKey: testStorageKey)
    XCTAssertEqual(newStore.filters.map(\.name), ["Filter 2", "Filter 1", "Filter 3"])
  }

  func testReorderEmptyIndexSetDoesNothing() throws {
    // 测试：空索引集不应该改变顺序
    let filter1 = TagFilter(mode: .any, tagIDs: [1])
    try store.save(filter: filter1, named: "Filter 1")

    let originalOrder = store.filters.map(\.name)
    store.reorder(from: IndexSet(), to: 0)

    XCTAssertEqual(store.filters.map(\.name), originalOrder)
  }

  // MARK: - Promote Tests

  func testPromoteFilter() throws {
    // 测试：提升筛选器到顶部
    let filter1 = TagFilter(mode: .any, tagIDs: [1])
    let filter2 = TagFilter(mode: .any, tagIDs: [2])
    let filter3 = TagFilter(mode: .any, tagIDs: [3])

    try store.save(filter: filter1, named: "Filter 1")
    try store.save(filter: filter2, named: "Filter 2")
    try store.save(filter: filter3, named: "Filter 3")

    // 当前顺序：Filter 3, Filter 2, Filter 1
    let filter1ID = store.filters.first { $0.name == "Filter 1" }!.id

    // 提升 Filter 1 到顶部
    store.promoteFilter(id: filter1ID)

    // 新顺序应该是：Filter 1, Filter 3, Filter 2
    XCTAssertEqual(store.filters.map(\.name), ["Filter 1", "Filter 3", "Filter 2"])

    // 验证持久化
    let newStore = TagSmartFilterStore(storageKey: testStorageKey)
    XCTAssertEqual(newStore.filters.first?.name, "Filter 1")
  }

  func testPromoteNonexistentFilterDoesNothing() throws {
    // 测试：提升不存在的筛选器不应该报错
    let filter = TagFilter(mode: .any, tagIDs: [1])
    try store.save(filter: filter, named: "Filter 1")

    let originalOrder = store.filters.map(\.name)
    store.promoteFilter(id: UUID())

    XCTAssertEqual(store.filters.map(\.name), originalOrder)
  }

  // MARK: - Persistence Tests

  func testImmediatePersistence() throws {
    // 测试：修改应该立即持久化（无防抖延迟）
    let filter = TagFilter(mode: .any, tagIDs: [1])
    try store.save(filter: filter, named: "Test")

    // 立即创建新 store，数据应该已经持久化
    let newStore = TagSmartFilterStore(storageKey: testStorageKey)
    XCTAssertEqual(newStore.filters.count, 1)
    XCTAssertEqual(newStore.filters.first?.name, "Test")
  }

  func testMultipleRapidChanges() throws {
    // 测试：快速连续修改应该都被持久化
    for i in 1...10 {
      let filter = TagFilter(mode: .any, tagIDs: [Int64(i)])
      try store.save(filter: filter, named: "Filter \(i)")
    }

    XCTAssertEqual(store.filters.count, 10)

    // 验证持久化（UserDefaults 应该自动批量写入）
    let newStore = TagSmartFilterStore(storageKey: testStorageKey)
    XCTAssertEqual(newStore.filters.count, 10)
  }

  // MARK: - Edge Cases

  func testComplexFilterPersistence() throws {
    // 测试：复杂筛选器的持久化
    let complexFilter = TagFilter(
      mode: .all,
      tagIDs: [1, 2, 3, 4, 5],
      keyword: "vacation 2023",
      colorHexes: ["#FF0000", "#00FF00", "#0000FF"]
    )

    try store.save(filter: complexFilter, named: "Complex Filter")

    let newStore = TagSmartFilterStore(storageKey: testStorageKey)
    let loaded = newStore.filters.first?.filter

    XCTAssertEqual(loaded?.mode, .all)
    XCTAssertEqual(loaded?.tagIDs, [1, 2, 3, 4, 5])
    XCTAssertEqual(loaded?.keyword, "vacation 2023")
    XCTAssertEqual(loaded?.colorHexes, ["#FF0000", "#00FF00", "#0000FF"])
  }

  func testUnicodeNamePersistence() throws {
    // 测试：Unicode 名称的持久化
    let filter = TagFilter(mode: .any, tagIDs: [1])
    let unicodeName = "🏖️ 假期照片 2023"

    try store.save(filter: filter, named: unicodeName)

    let newStore = TagSmartFilterStore(storageKey: testStorageKey)
    XCTAssertEqual(newStore.filters.first?.name, unicodeName)
  }
}
