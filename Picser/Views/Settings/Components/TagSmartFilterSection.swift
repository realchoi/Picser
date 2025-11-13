//
//  TagSmartFilterSection.swift
//  Picser
//
//  Created by Eric Cai on 2025/11/11.
//

import SwiftUI

struct TagSmartFilterSection: View {
  let filters: [TagSmartFilter]
  let tagNameLookup: [Int64: String]
  let activeFilterID: TagSmartFilter.ID?
  let onApply: (TagSmartFilter) -> Void
  let onRename: (TagSmartFilter) -> Void
  let onDelete: (TagSmartFilter) -> Void
  let showsContainer: Bool
  let showsTitle: Bool

  init(
    filters: [TagSmartFilter],
    tagNameLookup: [Int64: String],
    activeFilterID: TagSmartFilter.ID?,
    onApply: @escaping (TagSmartFilter) -> Void,
    onRename: @escaping (TagSmartFilter) -> Void,
    onDelete: @escaping (TagSmartFilter) -> Void,
    showsContainer: Bool = true,
    showsTitle: Bool = true
  ) {
    self.filters = filters
    self.tagNameLookup = tagNameLookup
    self.activeFilterID = activeFilterID
    self.onApply = onApply
    self.onRename = onRename
    self.onDelete = onDelete
    self.showsContainer = showsContainer
    self.showsTitle = showsTitle
  }

  var body: some View {
    Group {
      if showsContainer {
        GroupBox {
          content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
      } else {
        content
      }
    }
  }

  private var content: some View {
    VStack(alignment: .leading, spacing: 12) {
      if showsTitle {
        Text(L10n.string("tag_settings_smart_filters_title"))
          .font(.headline)
      }
      filterList
    }
    .padding(12)
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private var filterList: some View {
    let height = listHeight(for: filters.count)
    return ScrollView {
      VStack(spacing: 0) {
        if filters.isEmpty {
          Text(L10n.string("tag_settings_smart_filters_empty"))
            .font(.footnote)
            .foregroundColor(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 16)
        } else {
          ForEach(filters) { filter in
            row(for: filter)
            if filter.id != filters.last?.id {
              Divider()
            }
          }
        }
      }
      .padding(.vertical, 6)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(
        RoundedRectangle(cornerRadius: 12, style: .continuous)
          .fill(.quaternary)
      )
      .padding(.horizontal, 2)
    }
    .frame(height: height)
    .scrollIndicators(.automatic)
  }

  private func row(for filter: TagSmartFilter) -> some View {
    let isSelected = activeFilterID == filter.id
    return HStack(alignment: .center, spacing: 12) {
      VStack(alignment: .leading, spacing: 4) {
        Text(filter.name)
          .font(.headline)
          .lineLimit(1)
        let summary = summaryText(for: filter)
        if !summary.isEmpty {
          Text(summary)
            .font(.caption)
            .foregroundColor(.secondary)
        }
      }
      Spacer()
      Button {
        onApply(filter)
      } label: {
        Label(L10n.string("tag_settings_smart_filters_apply"), systemImage: isSelected ? "checkmark.circle.fill" : "checkmark.circle")
          .labelStyle(.iconOnly)
      }
      .buttonStyle(.borderless)
      .help(L10n.string("tag_settings_smart_filters_apply"))

      Button {
        onRename(filter)
      } label: {
        Label(L10n.string("tag_settings_smart_filters_rename"), systemImage: "pencil")
          .labelStyle(.iconOnly)
      }
      .buttonStyle(.borderless)
      .help(L10n.string("tag_settings_smart_filters_rename"))

      Button(role: .destructive) {
        onDelete(filter)
      } label: {
        Label(L10n.string("tag_settings_smart_filters_delete"), systemImage: "trash")
          .labelStyle(.iconOnly)
      }
      .buttonStyle(.borderless)
      .help(L10n.string("tag_settings_smart_filters_delete"))
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 8)
    .background(
      RoundedRectangle(cornerRadius: 10, style: .continuous)
        .fill(isSelected ? Color.accentColor.opacity(0.08) : Color.clear)
    )
  }

  private func listHeight(for count: Int) -> CGFloat {
    let rowHeight: CGFloat = 56
    if count == 0 {
      return rowHeight * 2
    }
    let minHeight = rowHeight * min(CGFloat(count), 3)
    let totalHeight = CGFloat(count) * rowHeight + 12
    let maxHeight: CGFloat = 320
    return min(max(totalHeight, minHeight), maxHeight)
  }

  private func summaryText(for filter: TagSmartFilter) -> String {
    var parts: [String] = []
    let modeText = modeDescription(filter.filter.mode)
    parts.append(String(format: L10n.string("tag_settings_smart_filters_summary_mode"), modeText))

    if !filter.filter.tagIDs.isEmpty {
      let names = filter.filter.tagIDs.compactMap { tagNameLookup[$0] }.sorted()
      let label: String
      if names.isEmpty {
        label = String(
          format: L10n.string("tag_settings_smart_filters_summary_tags_fallback"),
          filter.filter.tagIDs.count
        )
      } else {
        label = names.joined(separator: " / ")
      }
      parts.append(String(format: L10n.string("tag_settings_smart_filters_summary_tags"), label))
    }

    let keyword = filter.filter.keyword.trimmingCharacters(in: .whitespacesAndNewlines)
    if !keyword.isEmpty {
      parts.append(
        String(format: L10n.string("tag_settings_smart_filters_summary_keyword"), keyword)
      )
    }

    if !filter.filter.colorHexes.isEmpty {
      let colors = filter.filter.colorHexes.sorted().joined(separator: ", ")
      parts.append(
        String(format: L10n.string("tag_settings_smart_filters_summary_colors"), colors)
      )
    }

    return parts.joined(separator: " · ")
  }

  private func modeDescription(_ mode: TagFilterMode) -> String {
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
