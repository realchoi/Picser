//
//  TagSmartFilterStore.swift
//
//  Created by Eric Cai on 2025/11/10.
//

import Foundation
import Combine

/// 智能筛选器持久化存储
///
/// 管理用户自定义的标签筛选器，并使用 UserDefaults 进行持久化。
/// UserDefaults 本身是线程安全的，并且会自动批量写入磁盘，因此不需要额外的防抖逻辑。
///
/// 线程安全：使用 @MainActor 隔离，确保所有操作在主线程执行
@MainActor
final class TagSmartFilterStore: ObservableObject {
  /// 当前的智能筛选器列表
  @Published private(set) var filters: [TagSmartFilter] = []

  /// UserDefaults 存储键
  private let storageKey: String

  /// 初始化存储
  /// - Parameter storageKey: UserDefaults 存储键，默认为 "tag.smartFilters"
  init(storageKey: String = "tag.smartFilters") {
    self.storageKey = storageKey
    load()
  }

  /// 将指定筛选器提升到列表顶部
  ///
  /// 用于实现"最近使用"功能，将常用筛选器排在前面
  /// - Parameter id: 筛选器 ID
  func promoteFilter(id: TagSmartFilter.ID) {
    mutateFilters {
      guard let index = $0.firstIndex(where: { $0.id == id }) else { return }
      let item = $0.remove(at: index)
      $0.insert(item, at: 0)
    }
  }

  /// 保存新的智能筛选器
  ///
  /// - Parameters:
  ///   - filter: 要保存的筛选器配置
  ///   - name: 筛选器名称
  /// - Throws: SmartFilterStoreError.duplicateName 如果名称已存在
  ///          SmartFilterStoreError.duplicateFilter 如果相同筛选器已存在
  func save(filter: TagFilter, named name: String) throws {
    let sanitizedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !sanitizedName.isEmpty else { return }

    // 检查重复名称
    if hasDuplicateName(sanitizedName) {
      throw SmartFilterStoreError.duplicateName
    }

    // 检查重复筛选器
    if filters.contains(where: { $0.filter == filter }) {
      throw SmartFilterStoreError.duplicateFilter
    }

    mutateFilters { filters in
      let smartFilter = TagSmartFilter(name: sanitizedName, filter: filter)
      filters.insert(smartFilter, at: 0)
    }
  }

  /// 删除指定筛选器
  ///
  /// - Parameter id: 要删除的筛选器 ID
  func delete(id: TagSmartFilter.ID) {
    mutateFilters {
      $0.removeAll { $0.id == id }
    }
  }

  /// 重命名筛选器
  ///
  /// - Parameters:
  ///   - id: 筛选器 ID
  ///   - newName: 新名称
  /// - Throws: SmartFilterStoreError.duplicateName 如果新名称已被其他筛选器使用
  func rename(id: TagSmartFilter.ID, to newName: String) throws {
    let sanitizedName = newName.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !sanitizedName.isEmpty else { return }
    guard filters.contains(where: { $0.id == id }) else { return }

    // 检查重复名称（排除当前筛选器）
    if hasDuplicateName(sanitizedName, excludingID: id) {
      throw SmartFilterStoreError.duplicateName
    }

    mutateFilters {
      guard let index = $0.firstIndex(where: { $0.id == id }) else { return }
      $0[index].name = sanitizedName
    }
  }

  /// 重新排序筛选器列表
  ///
  /// - Parameters:
  ///   - source: 要移动的索引集合
  ///   - destination: 目标位置
  func reorder(from source: IndexSet, to destination: Int) {
    guard !source.isEmpty else { return }
    mutateFilters { filters in
      let moving = source.sorted().map { filters[$0] }
      for index in source.sorted(by: >) {
        filters.remove(at: index)
      }
      let adjustedDestination = max(
        0,
        min(destination - source.filter { $0 < destination }.count, filters.count)
      )
      filters.insert(contentsOf: moving, at: adjustedDestination)
    }
  }

  // MARK: - Persistence

  /// 从 UserDefaults 加载筛选器列表
  private func load() {
    guard let data = UserDefaults.standard.data(forKey: storageKey) else { return }
    do {
      let decoded = try JSONDecoder().decode([TagSmartFilter].self, from: data)
      filters = decoded
    } catch {
      print("Failed to load smart filters: \(error)")
    }
  }

  /// 将筛选器列表持久化到 UserDefaults
  ///
  /// UserDefaults 会自动批量写入磁盘，无需手动防抖。
  /// 即使快速连续调用，UserDefaults 也会合并写入操作。
  private func persist() {
    do {
      let data = try JSONEncoder().encode(filters)
      UserDefaults.standard.set(data, forKey: storageKey)
    } catch {
      print("Failed to persist smart filters: \(error)")
    }
  }

  // MARK: - Helpers

  /// 检查名称是否重复
  ///
  /// - Parameters:
  ///   - name: 要检查的名称
  ///   - excludingID: 排除的筛选器 ID（用于重命名时排除自身）
  /// - Returns: 如果名称重复返回 true
  private func hasDuplicateName(_ name: String, excludingID: TagSmartFilter.ID? = nil) -> Bool {
    filters.contains { candidate in
      if let excludingID, candidate.id == excludingID {
        return false
      }
      return candidate.name.caseInsensitiveCompare(name) == .orderedSame
    }
  }

  /// 修改筛选器列表并自动持久化
  ///
  /// 这是所有修改操作的统一入口，确保每次修改都会被保存。
  /// UserDefaults 是线程安全的，并且写入操作非常快（通常 < 1ms）。
  ///
  /// - Parameter block: 修改闭包
  private func mutateFilters(_ block: (inout [TagSmartFilter]) -> Void) {
    block(&filters)
    persist()  // 直接持久化，无需防抖
  }
}

/// 智能筛选器存储错误类型
enum SmartFilterStoreError: LocalizedError, Identifiable {
  case duplicateName
  case duplicateFilter

  var errorDescription: String? {
    switch self {
    case .duplicateName:
      return L10n.string("smart_filter_error_duplicate_name")
    case .duplicateFilter:
      return L10n.string("smart_filter_error_duplicate_filter")
    }
  }

  var id: String {
    switch self {
    case .duplicateName:
      return "duplicateName"
    case .duplicateFilter:
      return "duplicateFilter"
    }
  }
}
