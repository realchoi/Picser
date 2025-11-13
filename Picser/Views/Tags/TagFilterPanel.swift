//
//  TagFilterPanel.swift
//
//  Created by Eric Cai on 2025/11/08.
//

import SwiftUI

struct TagFilterPanel: View {
  @EnvironmentObject var tagService: TagService
  @Environment(\.locale) private var locale
  // MARK: - 视图状态
  @State private var smartFilterDraftName: String = ""
  @State private var showingSmartFilterSheet = false
  @State private var colorSearchText: String = ""
  @State private var tagSearchText: String = ""
  @FocusState private var keywordFocused: Bool

  var body: some View {
    VStack(spacing: 0) {
      headerRow
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
      Divider()
      VStack(alignment: .leading, spacing: 0) {
        keywordSection
        if !availableColors.isEmpty {
          sectionDivider
          colorSection
        }
        sectionDivider
        tagSelectionSection
        if !tagService.smartFilters.isEmpty {
          sectionDivider
          smartFilterSection
        }
      }
      .padding(12)
      Divider()
      footerRow
        .padding(12)
        .frame(maxWidth: .infinity)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(
      RoundedRectangle(cornerRadius: 12, style: .continuous)
        .fill(Color.secondary.opacity(0.08))
    )
    .padding(.horizontal, 4)
    .padding(.vertical, 2)
    .sheet(isPresented: $showingSmartFilterSheet) {
      SmartFilterNameSheet(
        name: $smartFilterDraftName,
        titleKey: "tag_filter_smart_sheet_title",
        placeholderKey: "tag_filter_smart_sheet_placeholder",
        actionKey: "tag_filter_smart_sheet_save_button"
      ) { name in
        try tagService.saveCurrentFilterAsSmart(named: name)
      }
      .frame(width: 320)
    }
  }

  /// 顶部模式切换 + 智能筛选保存按钮
  private var headerRow: some View {
    HStack(spacing: 12) {
      modeMenu
      Spacer()
      Button {
        presentSmartFilterSheet()
      } label: {
        Label(L10n.string("tag_filter_smart_save_button"), systemImage: "bookmark.badge.plus")
      }
      .buttonStyle(.borderless)
      .disabled(!tagService.activeFilter.isActive)
    }
  }

  /// 文本关键字输入区
  private var keywordSection: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(L10n.string("tag_filter_keyword_label"))
        .font(.caption)
        .foregroundColor(.secondary)
      TextField(
        L10n.string("tag_filter_keyword_placeholder"),
        text: keywordBinding
      )
      .textFieldStyle(.roundedBorder)
      .focused($keywordFocused)
      .onSubmit(commitKeyword)
    }
  }

  /// 标签颜色过滤区，支持多选
  private var colorSection: some View {
    let canClearColors = !tagService.activeFilter.colorHexes.isEmpty
    return VStack(alignment: .leading, spacing: 6) {
      HStack(spacing: 8) {
        Text(L10n.string("tag_filter_color_title"))
          .font(.caption)
          .foregroundColor(.secondary)
        Spacer()
        Text(colorSelectionSummary)
          .font(.caption)
          .foregroundColor(.secondary)
        Button(L10n.string("tag_filter_color_clear_button")) {
          guard canClearColors else { return }
          tagService.clearColorFilters()
        }
        .buttonStyle(.borderless)
        .allowsHitTesting(canClearColors)
        .opacity(canClearColors ? 1 : disabledButtonOpacity)
      }
      TextField(
        L10n.string("tag_filter_color_search_placeholder"),
        text: $colorSearchText
      )
      .textFieldStyle(.roundedBorder)
      Group {
        if filteredColors.isEmpty {
          EmptyView()
        } else if filteredColors.count <= colorInlineLimit {
          colorGridContent(filteredColors)
        } else {
          ScrollView {
            colorGridContent(filteredColors)
          }
          .frame(maxHeight: colorScrollMaxHeight)
        }
      }
      .frame(maxWidth: .infinity)
      if filteredColors.isEmpty {
        Text(L10n.string("tag_filter_color_search_empty"))
          .font(.caption)
          .foregroundColor(.secondary)
      }
    }
  }

  /// 智能筛选器列表
  private var smartFilterSection: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(L10n.string("tag_filter_smart_section_title"))
        .font(.caption)
        .foregroundColor(.secondary)
      ScrollView(.horizontal, showsIndicators: true) {
        HStack(spacing: 8) {
          ForEach(tagService.smartFilters) { filter in
            Button {
              tagService.applySmartFilter(filter)
            } label: {
              smartFilterChip(for: filter)
            }
            .buttonStyle(.plain)
          }
        }
        .padding(.vertical, 2)
      }
      .frame(maxWidth: .infinity)
    }
  }

  private var sectionDivider: some View {
    Divider()
      .padding(.vertical, 10)
  }

  private var emptyStateView: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(L10n.string("tag_filter_empty_hint"))
        .font(.footnote)
        .foregroundColor(.secondary)
    }
  }

  /// 底部清除按钮区域，保持与顶部工具条一致
  private var footerRow: some View {
    let canClearAll = tagService.activeFilter.isActive
    return HStack {
      Spacer()
      Button {
        guard canClearAll else { return }
        tagService.clearFilter()
      } label: {
        Label(L10n.string("tag_filter_clear_button"), systemImage: "xmark.circle")
      }
      .buttonStyle(.borderless)
      .allowsHitTesting(canClearAll)
      .opacity(canClearAll ? 1 : disabledButtonOpacity)
    }
  }

  private var modeMenu: some View {
    Menu {
      ForEach(TagFilterMode.allCases, id: \.self) { mode in
        Button {
          tagService.activeFilter.mode = mode
        } label: {
          HStack {
            Text(title(for: mode))
            Spacer()
            if tagService.activeFilter.mode == mode {
              Image(systemName: "checkmark")
            }
          }
        }
      }
    } label: {
      Label(L10n.string("tag_filter_mode_button"), systemImage: "slider.horizontal.3")
    }
    .id("mode-menu-\(locale.identifier)")
  }

  /// 标签勾选区域，支持滚动与搜索
  private var tagSelectionSection: some View {
    Group {
      if tagService.scopedTags.isEmpty {
        emptyStateView
      } else {
        let canClearTags = !tagService.activeFilter.tagIDs.isEmpty
        VStack(alignment: .leading, spacing: 6) {
          HStack(spacing: 8) {
            Text(L10n.string("tag_filter_section_title"))
              .font(.caption)
              .foregroundColor(.secondary)
            Spacer()
            Text(selectionSummary)
              .font(.caption)
              .foregroundColor(.secondary)
            Button(L10n.string("tag_filter_tag_clear_button")) {
              guard canClearTags else { return }
              tagService.clearTagFilters()
            }
            .buttonStyle(.borderless)
            .allowsHitTesting(canClearTags)
            .opacity(canClearTags ? 1 : disabledButtonOpacity)
          }
          TextField(
            L10n.string("tag_filter_tag_search_placeholder"),
            text: $tagSearchText
          )
          .textFieldStyle(.roundedBorder)
          tagList
        }
      }
    }
  }

  /// 可滚动标签列表
  private var tagList: some View {
    ScrollView {
      LazyVStack(alignment: .leading, spacing: 4) {
        ForEach(filteredTags) { tag in
          tagRow(for: tag)
        }
      }
      .padding(.vertical, 2)
    }
    .frame(maxWidth: .infinity)
    .frame(minHeight: 120, maxHeight: 300)
    .overlay {
      if filteredTags.isEmpty {
        Text(L10n.string("tag_filter_tag_search_empty"))
          .font(.caption)
          .foregroundColor(.secondary)
          .padding(.top, 8)
      }
    }
  }

  private var selectionSummary: String {
    let count = tagService.activeFilter.tagIDs.count
    if count == 0 {
      return L10n.string("tag_filter_selection_summary_none")
    }
    return String(format: L10n.string("tag_filter_selection_summary_some"), count)
  }

  private var colorSelectionSummary: String {
    let count = tagService.activeFilter.colorHexes.count
    if count == 0 {
      return L10n.string("tag_filter_color_summary_none")
    }
    return String(format: L10n.string("tag_filter_color_summary_some"), count)
  }

  private func tagUsageSummary(for count: Int) -> String {
    String(format: L10n.string("tag_usage_format"), count)
  }

  /// 自定义 Binding，实时写入 TagService
  private var keywordBinding: Binding<String> {
    Binding(
      get: { tagService.activeFilter.keyword },
      set: { tagService.updateKeywordFilter($0) }
    )
  }

  /// 手动结束编辑时再走一次 trim，保证条件准确
  private func commitKeyword() {
    tagService.updateKeywordFilter(
      tagService.activeFilter.keyword.trimmingCharacters(in: .whitespacesAndNewlines)
    )
  }

  /// 从作用域 + 全部标签中提取去重后的颜色集合
  private var availableColors: [String] {
    let scoped = tagService.scopedTags.compactMap { $0.colorHex.normalizedHexColor() }
    let global = tagService.allTags.compactMap { $0.colorHex.normalizedHexColor() }
    return Array(Set(scoped + global)).sorted()
  }

  private var filteredColors: [String] {
    let query = colorSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !query.isEmpty else { return availableColors }
    return availableColors.filter { $0.localizedCaseInsensitiveContains(query) }
  }

  private var filteredTags: [ScopedTagSummary] {
    let query = tagSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !query.isEmpty else { return tagService.scopedTags }
    return tagService.scopedTags.filter { tag in
      tag.name.localizedCaseInsensitiveContains(query) ||
        "\(tag.usageCount)".localizedStandardContains(query)
    }
  }

  /// 当前筛选条件是否与某个智能筛选完全一致
  private var activeSmartFilterID: TagSmartFilter.ID? {
    tagService.smartFilters.first(where: { $0.filter == tagService.activeFilter })?.id
  }

  private var colorGridColumns: [GridItem] {
    Array(
      repeating: GridItem(.flexible(minimum: 80), spacing: 8, alignment: .leading),
      count: 3
    )
  }
  private let colorInlineLimit = 6
  private let colorScrollMaxHeight: CGFloat = 110
  private let disabledButtonOpacity: Double = 0.55

  /// 单个颜色过滤按钮，带选中态
  private func colorChip(for hex: String) -> some View {
    let isSelected = tagService.activeFilter.colorHexes.contains(hex)
    return Button {
      tagService.toggleColorFilter(hex: hex)
    } label: {
      HStack(spacing: 6) {
        TagColorIcon(hex: hex)
        Text(hex)
          .font(.caption)
          .foregroundColor(.primary)
      }
      .padding(.horizontal, 10)
      .padding(.vertical, 4)
      .background(
        Capsule()
          .fill(isSelected ? Color.accentColor.opacity(0.2) : Color.clear)
      )
      .overlay(
        Capsule()
          .stroke(
            isSelected ? Color.accentColor : Color.secondary.opacity(0.4),
            lineWidth: 1
          )
      )
    }
    .buttonStyle(.plain)
  }

  @ViewBuilder
  private func colorGridContent(_ colors: [String]) -> some View {
    LazyVGrid(columns: colorGridColumns, spacing: 8) {
      ForEach(colors, id: \.self) { hex in
        colorChip(for: hex)
      }
    }
    .padding(.vertical, 2)
  }

  /// 标签多选行
  private func tagRow(for tag: ScopedTagSummary) -> some View {
    let isSelected = tagService.activeFilter.tagIDs.contains(tag.id)
    return Button {
      tagService.toggleFilter(tagID: tag.id, mode: tagService.activeFilter.mode)
    } label: {
      HStack(spacing: 8) {
        TagColorIcon(hex: tag.colorHex)
        HStack(spacing: 6) {
          Text(tag.name)
            .font(.body)
            .lineLimit(1)
          Text("(\(tagUsageSummary(for: tag.usageCount)))")
            .font(.caption)
            .foregroundColor(.secondary)
            .lineLimit(1)
        }
        Spacer()
        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
          .foregroundColor(isSelected ? .accentColor : .secondary.opacity(0.6))
      }
      .padding(.horizontal, 8)
      .padding(.vertical, 6)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(
        RoundedRectangle(cornerRadius: 8, style: .continuous)
          .fill(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
      )
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
  }

  /// 弹出命名面板前先清空草稿
  private func presentSmartFilterSheet() {
    smartFilterDraftName = ""
    showingSmartFilterSheet = true
  }

  /// 智能筛选标签样式，支持高亮当前使用的一项
  private func smartFilterChip(for filter: TagSmartFilter) -> some View {
    let isSelected = activeSmartFilterID == filter.id
    return Text(filter.name)
      .lineLimit(1)
      .padding(.horizontal, 12)
      .padding(.vertical, 6)
      .background(
        Capsule()
          .fill(isSelected ? Color.accentColor : Color.accentColor.opacity(0.12))
      )
      .foregroundColor(isSelected ? Color.white : .primary)
      .overlay(
        Capsule()
          .stroke(
            isSelected ? Color.accentColor : Color.accentColor.opacity(0.4),
            lineWidth: 1
          )
      )
  }

  /// 统一 HEX 格式，避免大小写/符号差异
  /// 将模式枚举转换为本地化字符串
  private func title(for mode: TagFilterMode) -> String {
    switch mode {
    case .any:
      return L10n.string("tag_filter_mode_any")
    case .all:
      return L10n.string("tag_filter_mode_all")
    case .exclude:
      return L10n.string("tag_filter_mode_exclude")
    }
  }

}

/// 智能筛选命名弹窗，可复用在多个入口
struct SmartFilterNameSheet: View {
  @Environment(\.dismiss) private var dismiss
  @Binding var name: String
  let titleKey: String
  let placeholderKey: String
  let actionKey: String
  let onSave: (String) throws -> Void
  @State private var errorMessage: String?

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text(L10n.string(titleKey))
        .font(.headline)
      TextField(
        L10n.string(placeholderKey),
        text: $name
      )
      .textFieldStyle(.roundedBorder)
      .onSubmit(performSave)
      if let errorMessage {
        Text(errorMessage)
          .font(.caption)
          .foregroundColor(.pink)
      }
      HStack {
        Button(L10n.key("cancel_button"), role: .cancel) {
          dismiss()
        }
        Spacer()
        Button(L10n.string(actionKey)) {
          performSave()
        }
        .buttonStyle(.borderedProminent)
        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
      }
    }
    .padding(24)
    .onChange(of: name) { _, _ in
      errorMessage = nil
    }
  }

  private func performSave() {
    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return }
    do {
      try onSave(trimmed)
      errorMessage = nil
      dismiss()
    } catch {
      errorMessage = error.localizedDescription
    }
  }
}
