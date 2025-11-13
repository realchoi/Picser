//
//  TagSettingsStore.swift
//
//  Created by Eric Cai on 2025/11/11.
//

import SwiftUI

@MainActor
final class TagSettingsStore: ObservableObject {
  private let tagService: TagService
  private let defaults: UserDefaults
  private var colorUpdateTasks: [Int64: Task<Void, Never>] = [:]
  private var searchDebounceTask: Task<Void, Never>?
  private var colorDrafts: [Int64: Color] = [:]

  private static let searchKey = "tagSettings.search.text"
  private static let batchModeKey = "tagSettings.batchMode.enabled"
  private static let smartPanelExpandedKey = "tagSettings.smartPanelExpanded"
  private static let batchPanelExpandedKey = "tagSettings.batchPanelExpanded"

  @Published private(set) var searchText: String
  @Published private(set) var debouncedSearchText: String
  @Published var isBatchModeEnabled: Bool {
    didSet {
      guard oldValue != isBatchModeEnabled else { return }
      defaults.set(isBatchModeEnabled, forKey: Self.batchModeKey)
      if !isBatchModeEnabled {
        resetSelection()
        isShowingDeleteConfirm = false
        isShowingClearAssignmentsConfirm = false
        isShowingMergeSheet = false
      }
    }
  }

  @Published var selectedTagIDs: Set<Int64> = []
  @Published var batchColor: Color = .accentColor
  @Published var isShowingDeleteConfirm = false
  @Published var isShowingClearAssignmentsConfirm = false
  @Published var isShowingMergeSheet = false
  @Published var mergeTargetName: String = ""
  @Published var isSmartPanelExpanded: Bool {
    didSet {
      guard oldValue != isSmartPanelExpanded else { return }
      defaults.set(isSmartPanelExpanded, forKey: Self.smartPanelExpandedKey)
    }
  }
  @Published var isBatchPanelExpanded: Bool {
    didSet {
      guard oldValue != isBatchPanelExpanded else { return }
      defaults.set(isBatchPanelExpanded, forKey: Self.batchPanelExpandedKey)
    }
  }

  init(tagService: TagService, defaults: UserDefaults = .standard) {
    self.tagService = tagService
    self.defaults = defaults
    let storedSearch = defaults.string(forKey: Self.searchKey) ?? ""
    self.searchText = storedSearch
    self.debouncedSearchText = storedSearch
    self.isBatchModeEnabled = defaults.bool(forKey: Self.batchModeKey)
    self.isSmartPanelExpanded = defaults.bool(forKey: Self.smartPanelExpandedKey)
    self.isBatchPanelExpanded = defaults.bool(forKey: Self.batchPanelExpandedKey)
  }

  // MARK: - Search

  var searchBinding: Binding<String> {
    Binding(
      get: { self.searchText },
      set: { self.updateSearchText($0) }
    )
  }

  private func updateSearchText(_ text: String) {
    guard text != searchText else { return }
    searchText = text
    defaults.set(text, forKey: Self.searchKey)
    scheduleSearchDebounce(for: text)
  }

  private func scheduleSearchDebounce(for keyword: String) {
    searchDebounceTask?.cancel()
    searchDebounceTask = Task { [weak self] in
      try? await Task.sleep(nanoseconds: 250_000_000)
      guard !Task.isCancelled, let self else { return }
      debouncedSearchText = keyword
    }
  }

  // MARK: - Batch selection

  func selectionBinding(for tagID: Int64) -> Binding<Bool> {
    Binding(
      get: { self.selectedTagIDs.contains(tagID) },
      set: { isSelected in
        if isSelected {
          self.selectedTagIDs.insert(tagID)
        } else {
          self.selectedTagIDs.remove(tagID)
        }
      }
    )
  }

  func pruneSelection(availableIDs: Set<Int64>) {
    selectedTagIDs = selectedTagIDs.intersection(availableIDs)
  }

  func applyBatchColor() {
    guard !selectedTagIDs.isEmpty else { return }
    let ids = selectedTagIDs
    let hex = batchColor.hexString()
    Task {
      await tagService.updateColor(tagIDs: ids, hex: hex)
    }
  }

  func clearBatchColor() {
    guard !selectedTagIDs.isEmpty else { return }
    let ids = selectedTagIDs
    Task {
      await tagService.updateColor(tagIDs: ids, hex: nil)
    }
  }

  func performBatchDelete() {
    guard !selectedTagIDs.isEmpty else { return }
    let ids = selectedTagIDs
    Task {
      await tagService.deleteTags(ids)
      await MainActor.run {
        self.isShowingDeleteConfirm = false
        self.isBatchModeEnabled = false
      }
    }
  }

  func performClearAssignments() {
    guard !selectedTagIDs.isEmpty else { return }
    let ids = selectedTagIDs
    Task {
      await tagService.clearAssignments(for: ids)
      await MainActor.run {
        self.isShowingClearAssignmentsConfirm = false
      }
    }
  }

  func performMerge(targetName: String) {
    guard !selectedTagIDs.isEmpty else { return }
    let trimmed = targetName.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty, selectedTagIDs.count >= 2 else { return }
    let ids = selectedTagIDs
    Task {
      await tagService.mergeTags(sourceIDs: ids, targetName: trimmed)
      await MainActor.run {
        self.mergeTargetName = ""
        self.isShowingMergeSheet = false
        self.isBatchModeEnabled = false
      }
    }
  }

  private func resetSelection() {
    selectedTagIDs.removeAll()
    mergeTargetName = ""
  }

  // MARK: - Tag color editing

  func colorBinding(for tag: TagRecord) -> Binding<Color> {
    Binding(
      get: { self.colorDrafts[tag.id] ?? Color(hexString: tag.colorHex) ?? .accentColor },
      set: { newValue in
        self.colorDrafts[tag.id] = newValue
        self.scheduleColorUpdate(tagID: tag.id, color: newValue)
      }
    )
  }

  func canClearColor(for tag: TagRecord) -> Bool {
    colorDrafts[tag.id] != nil || tag.colorHex != nil
  }

  func clearColor(for tag: TagRecord) {
    colorDrafts[tag.id] = nil
    scheduleColorUpdate(tagID: tag.id, color: nil)
  }

  func pruneColorDrafts(using tags: [TagRecord]) {
    let tagIndex = Dictionary(uniqueKeysWithValues: tags.map { ($0.id, $0) })
    colorDrafts = colorDrafts.filter { id, draftColor in
      guard let tag = tagIndex[id] else { return false }
      guard
        let draftHex = draftColor.hexString(),
        let actualHex = tag.colorHex
      else {
        return true
      }
      return draftHex.caseInsensitiveCompare(actualHex) != .orderedSame
    }
  }

  private func scheduleColorUpdate(tagID: Int64, color: Color?) {
    colorUpdateTasks[tagID]?.cancel()
    let hexValue = color?.hexString()
    colorUpdateTasks[tagID] = Task {
      try? await Task.sleep(nanoseconds: 200_000_000)
      if Task.isCancelled { return }
      await tagService.updateColor(tagID: tagID, hex: hexValue)
      await MainActor.run {
        self.colorUpdateTasks[tagID] = nil
      }
    }
  }

  // MARK: - Lifecycle

  func teardown() {
    searchDebounceTask?.cancel()
    searchDebounceTask = nil
    colorUpdateTasks.values.forEach { $0.cancel() }
    colorUpdateTasks.removeAll()
  }
}
