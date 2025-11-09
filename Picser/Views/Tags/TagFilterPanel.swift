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
  @FocusState private var keywordFocused: Bool

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      headerRow
      keywordSection
      if !availableColors.isEmpty {
        colorSection
      }
      if tagService.scopedTags.isEmpty {
        emptyStateView
      } else {
        tagSelectionMenu
      }
      if !tagService.smartFilters.isEmpty {
        smartFilterSection
      }
      if tagService.activeFilter.isActive {
        clearButton
      }
    }
    .padding(10)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(
      RoundedRectangle(cornerRadius: 12, style: .continuous)
        .fill(Color.secondary.opacity(0.08))
    )
    .sheet(isPresented: $showingSmartFilterSheet) {
      SmartFilterNameSheet(
        name: $smartFilterDraftName,
        titleKey: "tag_filter_smart_sheet_title",
        placeholderKey: "tag_filter_smart_sheet_placeholder",
        actionKey: "tag_filter_smart_sheet_save_button"
      ) { name in
        tagService.saveCurrentFilterAsSmart(named: name)
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
    VStack(alignment: .leading, spacing: 6) {
      HStack {
        Text(L10n.string("tag_filter_color_title"))
          .font(.caption)
          .foregroundColor(.secondary)
        Spacer()
        if !tagService.activeFilter.colorHexes.isEmpty {
          Button(L10n.string("tag_filter_color_clear_button")) {
            tagService.clearColorFilters()
          }
          .buttonStyle(.borderless)
        }
      }
      ScrollView(.horizontal, showsIndicators: true) {
        HStack(spacing: 8) {
          ForEach(availableColors, id: \.self) { hex in
            colorChip(for: hex)
          }
        }
        .padding(.vertical, 2)
      }
      .frame(maxWidth: .infinity)
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

  private var emptyStateView: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(L10n.string("tag_filter_empty_hint"))
        .font(.footnote)
        .foregroundColor(.secondary)
    }
  }

  /// 一键清空所有筛选条件
  private var clearButton: some View {
    Button {
      tagService.clearFilter()
    } label: {
      Label(L10n.string("tag_filter_clear_button"), systemImage: "xmark.circle")
    }
    .buttonStyle(.borderless)
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

  /// 标签勾选列表，可切换 ANY/ALL/EXCLUDE
  private var tagSelectionMenu: some View {
    Menu {
      ForEach(tagService.scopedTags) { tag in
        Button {
          tagService.toggleFilter(tagID: tag.id, mode: tagService.activeFilter.mode)
        } label: {
          tagMenuTitle(
            name: tag.name,
            usageCount: tag.usageCount,
            hex: tag.colorHex,
            isSelected: tagService.activeFilter.tagIDs.contains(tag.id)
          )
        }
      }
      if tagService.activeFilter.isActive {
        Divider()
        clearButton
      }
    } label: {
      Label(selectionSummary, systemImage: "tag")
    }
    .id("tag-menu-\(locale.identifier)")
  }

  private var selectionSummary: String {
    let count = tagService.activeFilter.tagIDs.count
    if count == 0 {
      return L10n.string("tag_filter_selection_summary_none")
    }
    return String(format: L10n.string("tag_filter_selection_summary_some"), count)
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

  /// 从作用域标签中提取去重后的颜色集合
  private var availableColors: [String] {
    let colors = tagService.scopedTags
      .compactMap { normalizedHex($0.colorHex) }
    return Array(Set(colors)).sorted()
  }

  /// 当前筛选条件是否与某个智能筛选完全一致
  private var activeSmartFilterID: TagSmartFilter.ID? {
    tagService.smartFilters.first(where: { $0.filter == tagService.activeFilter })?.id
  }

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
  private func normalizedHex(_ hex: String?) -> String? {
    guard var value = hex?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
      return nil
    }
    if value.hasPrefix("#") {
      value.removeFirst()
    }
    guard !value.isEmpty else { return nil }
    return "#\(value.uppercased())"
  }

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
  let onSave: (String) -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text(L10n.string(titleKey))
        .font(.headline)
      TextField(
        L10n.string(placeholderKey),
        text: $name
      )
      .textFieldStyle(.roundedBorder)
      HStack {
        Button(L10n.key("cancel_button"), role: .cancel) {
          dismiss()
        }
        Spacer()
        Button(L10n.string(actionKey)) {
          let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
          guard !trimmed.isEmpty else { return }
          onSave(trimmed)
          dismiss()
        }
        .buttonStyle(.borderedProminent)
        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
      }
    }
    .padding(24)
  }
}
