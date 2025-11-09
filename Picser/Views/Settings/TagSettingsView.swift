//
//  TagSettingsView.swift
//
//  Created by Eric Cai on 2025/11/08.
//

import SwiftUI

struct TagSettingsView: View {
  @EnvironmentObject var tagService: TagService

  // MARK: - 视图状态
  @State private var editingTag: TagRecord?
  @State private var deletingTag: TagRecord?
  @State private var isInspecting = false
  // 批量编辑相关的控制状态
  @State private var batchMode = false
  @State private var selectedTagIDs: Set<Int64> = []
  @State private var batchColor: Color = .accentColor
  @State private var showingBatchDeleteConfirm = false
  @State private var showingClearAssignmentsConfirm = false
  @State private var showingBatchAddSheet = false
  @State private var showingMergeSheet = false
  @State private var showingCleanupConfirm = false
  @State private var batchAddInput: String = ""
  @State private var mergeTargetName: String = ""
  @State private var searchText: String = ""
  @State private var colorDrafts: [Int64: Color] = [:]
  // 智能筛选命名/删除状态
  @State private var renamingSmartFilter: TagSmartFilter?
  @State private var smartFilterRenameText: String = ""
  @State private var deletingSmartFilter: TagSmartFilter?

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      inspectionSummaryCard
      statsCard
      smartFilterCard
      batchControls
      searchField

      if tagService.allTags.isEmpty {
        emptyState
      } else if filteredTags.isEmpty {
        filteredEmptyState
      } else {
        tagListSection
      }

      HStack(spacing: 12) {
        Button {
          showingCleanupConfirm = true
        } label: {
          Label(L10n.string("tag_settings_cleanup_button"), systemImage: "trash.slash")
        }

        Spacer()

        Button {
          Task { await tagService.refreshAllTags() }
        } label: {
          Label(L10n.string("tag_settings_refresh_button"), systemImage: "arrow.clockwise.circle")
        }
      }
    }
    .settingsContentContainer()
    .sheet(item: $editingTag) { tag in
      TagRenameSheet(tag: tag) { newName in
        Task { await tagService.rename(tagID: tag.id, to: newName) }
      }
    }
    .sheet(isPresented: $showingBatchAddSheet) {
      TagBatchAddSheet(text: $batchAddInput) { names in
        Task { await tagService.addTags(names: names) }
      }
    }
    .sheet(isPresented: $showingMergeSheet) {
      TagMergeSheet(
        mergeTarget: $mergeTargetName,
        selectedCount: selectedTagIDs.count
      ) { target in
        performMerge(targetName: target)
      }
    }
    .sheet(item: $renamingSmartFilter) { filter in
      SmartFilterNameSheet(
        name: $smartFilterRenameText,
        titleKey: "tag_settings_smart_sheet_title",
        placeholderKey: "tag_filter_smart_sheet_placeholder",
        actionKey: "tag_settings_smart_sheet_save_button"
      ) { newName in
        tagService.renameSmartFilter(id: filter.id, to: newName)
        renamingSmartFilter = nil
      }
      .frame(width: 320)
    }
    .alert(
      L10n.string("tag_settings_delete_title"),
      isPresented: Binding(
        get: { deletingTag != nil },
        set: { if !$0 { deletingTag = nil } }
      ),
      presenting: deletingTag
    ) { tag in
      Button(role: .destructive) {
        guard let deletingTag else { return }
        Task { await tagService.deleteTag(deletingTag.id) }
        self.deletingTag = nil
      } label: {
        Text(L10n.string("delete_button"))
      }
      Button(L10n.key("cancel_button"), role: .cancel) {
        deletingTag = nil
      }
    } message: { tag in
      Text(
        String(
          format: L10n.string("tag_settings_delete_message"),
          tag.name,
          tag.usageCount
        )
      )
    }
    .confirmationDialog(
      L10n.string("tag_settings_clear_assignments_title"),
      isPresented: $showingClearAssignmentsConfirm,
      titleVisibility: .visible
    ) {
      Button(L10n.string("tag_settings_clear_assignments_button"), role: .destructive) {
        performClearAssignments()
      }
      Button(L10n.key("cancel_button"), role: .cancel) {
        showingClearAssignmentsConfirm = false
      }
    }
    .confirmationDialog(
      L10n.string("tag_settings_cleanup_confirm_title"),
      isPresented: $showingCleanupConfirm,
      titleVisibility: .visible
    ) {
      Button(L10n.string("tag_settings_cleanup_button"), role: .destructive) {
        Task {
          await tagService.purgeUnusedTags()
          showingCleanupConfirm = false
        }
      }
      Button(L10n.key("cancel_button"), role: .cancel) {
        showingCleanupConfirm = false
      }
    }
    .confirmationDialog(
      L10n.string("tag_settings_batch_delete_dialog_title"),
      isPresented: $showingBatchDeleteConfirm,
      titleVisibility: .visible
    ) {
      Button(L10n.string("tag_settings_batch_delete_button"), role: .destructive) {
        performBatchDelete()
      }
      Button(L10n.key("cancel_button"), role: .cancel) {
        showingBatchDeleteConfirm = false
      }
    }
    .confirmationDialog(
      L10n.string("tag_settings_smart_delete_title"),
      isPresented: Binding(
        get: { deletingSmartFilter != nil },
        set: { if !$0 { deletingSmartFilter = nil } }
      ),
      titleVisibility: .visible,
      presenting: deletingSmartFilter
    ) { filter in
      Button(L10n.string("tag_settings_smart_delete_confirm"), role: .destructive) {
        tagService.deleteSmartFilter(id: filter.id)
        deletingSmartFilter = nil
      }
      Button(L10n.key("cancel_button"), role: .cancel) {
        deletingSmartFilter = nil
      }
    } message: { filter in
      Text(String(format: L10n.string("tag_settings_smart_delete_message"), filter.name))
    }
    .onChange(of: tagService.allTags) { _, tags in
      let existingIDs = Set(tags.map(\.id))
      selectedTagIDs = selectedTagIDs.intersection(existingIDs)
      colorDrafts = colorDrafts.filter { existingIDs.contains($0.key) }
    }
  }

  /// 初始无标签时的占位提示
  private var emptyState: some View {
    VStack(spacing: 12) {
      Image(systemName: "tag.slash")
        .font(.system(size: 42))
        .foregroundColor(.secondary)
      Text(L10n.string("tag_settings_empty"))
        .font(.callout)
        .foregroundColor(.secondary)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  /// 搜索结果为空时的提示
  private var filteredEmptyState: some View {
    VStack(spacing: 8) {
      Image(systemName: "magnifyingglass")
        .font(.system(size: 32))
        .foregroundColor(.secondary)
      Text(L10n.string("tag_settings_search_empty"))
        .font(.callout)
        .foregroundColor(.secondary)
    }
    .frame(maxWidth: .infinity, minHeight: 160)
  }

  /// 展示后台巡检状态的卡片
  private var inspectionSummaryCard: some View {
    GroupBox {
      VStack(alignment: .leading, spacing: 12) {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
          VStack(alignment: .leading, spacing: 4) {
            Text(L10n.string("tag_settings_inspection_title"))
              .font(.headline)
            Text(inspectionDescription)
              .font(.caption)
              .foregroundColor(.secondary)
          }
          Spacer()
          Button {
            runInspectionNow()
          } label: {
            Label {
              Text(
                L10n.string(
                  isInspecting
                    ? "tag_settings_inspection_running"
                    : "tag_settings_inspection_button"
                )
              )
            } icon: {
              ZStack {
                Image(systemName: "stethoscope")
                  .opacity(isInspecting ? 0 : 1)
                ProgressView()
                  .progressViewStyle(.circular)
                  .controlSize(.small)
                  .opacity(isInspecting ? 1 : 0)
              }
              .frame(width: 18, height: 18)
            }
            .labelStyle(.titleAndIcon)
          }
          .buttonStyle(.borderedProminent)
          .disabled(isInspecting)
        }

        if !tagService.lastInspection.missingPaths.isEmpty && !isInspecting {
          Divider()
          missingPathsView
        }
      }
      .padding(12)
    }
  }

  /// 标签数量相关统计卡片
  private var statsCard: some View {
    GroupBox {
      VStack(alignment: .leading, spacing: 12) {
        Text(L10n.string("tag_settings_stats_title"))
          .font(.headline)
        HStack {
          statColumn(title: L10n.string("tag_settings_stats_total"), value: totalTags)
          statColumn(title: L10n.string("tag_settings_stats_used"), value: usedTags)
          statColumn(title: L10n.string("tag_settings_stats_unused"), value: unusedTags)
        }
      }
      .padding(12)
    }
  }

  /// 智能筛选列表与操作入口
  private var smartFilterCard: some View {
    GroupBox {
      VStack(alignment: .leading, spacing: 12) {
        Text(L10n.string("tag_settings_smart_filters_title"))
          .font(.headline)
        smartFilterList
      }
      .padding(12)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  /// 顶部搜索框，支持清空按钮
  private var searchField: some View {
    HStack {
      Image(systemName: "magnifyingglass")
        .foregroundColor(.secondary)
      TextField(L10n.string("tag_settings_search_placeholder"), text: $searchText)
        .textFieldStyle(.plain)
        .autocorrectionDisabled()
      if !searchText.isEmpty {
        Button {
          searchText = ""
        } label: {
          Image(systemName: "xmark.circle.fill")
            .foregroundColor(.secondary)
        }
        .buttonStyle(.plain)
      }
    }
    .padding(8)
    .background(
      RoundedRectangle(cornerRadius: 10)
        .fill(Color.secondary.opacity(0.12))
    )
  }

  /// 批量操作控制区：切换模式、统一调色、批量删除
  private var batchControls: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack {
        Toggle(isOn: Binding(
          get: { batchMode },
          set: { value in
            batchMode = value
            if !value {
              selectedTagIDs.removeAll()
            }
          }
        )) {
          Label(L10n.string("tag_settings_batch_mode_toggle"), systemImage: "square.stack.3d.up")
        }
        .toggleStyle(.switch)

        Spacer()

        Button {
          showingBatchAddSheet = true
        } label: {
          Label(L10n.string("tag_settings_batch_add_button"), systemImage: "plus.circle")
        }
      }

      if batchMode {
        // 只有开启批量模式才展示颜色/删除等批处理控件
        VStack(alignment: .leading, spacing: 8) {
          HStack(spacing: 12) {
            Text(
              String(
                format: L10n.string("tag_settings_batch_selection_count"),
                selectedTagIDs.count
              )
            )
            .font(.caption)
            .foregroundColor(.secondary)

            ColorPicker(
              L10n.string("tag_settings_batch_color_picker"),
              selection: $batchColor,
              supportsOpacity: false
            )
            .labelsHidden()

            Button {
              applyBatchColor()
            } label: {
              Label(L10n.string("tag_settings_batch_apply_color"), systemImage: "paintpalette")
            }
            .buttonStyle(.borderedProminent)
            .disabled(selectedTagIDs.isEmpty)

            Button {
              clearBatchColor()
            } label: {
              Label(L10n.string("tag_settings_batch_clear_color"), systemImage: "eraser")
            }
            .buttonStyle(.bordered)
            .disabled(selectedTagIDs.isEmpty)

            Spacer()
          }

          HStack(spacing: 12) {
            Button {
              showingClearAssignmentsConfirm = true
            } label: {
              Label(L10n.string("tag_settings_clear_assignments_button"), systemImage: "minus.circle")
            }
            .disabled(selectedTagIDs.isEmpty)

            Button {
              mergeTargetName = ""
              showingMergeSheet = true
            } label: {
              Label(L10n.string("tag_settings_merge_button"), systemImage: "arrow.triangle.merge")
            }
            .disabled(selectedTagIDs.count < 2)

            Spacer()

            Button(role: .destructive) {
              showingBatchDeleteConfirm = true
            } label: {
              Label(L10n.string("tag_settings_batch_delete_button"), systemImage: "trash")
            }
            .disabled(selectedTagIDs.isEmpty)
          }
        }
      }
    }
  }

  private var missingPathsView: some View {
    let summary = tagService.lastInspection
    let preview = Array(summary.missingPaths.prefix(5))
    return VStack(alignment: .leading, spacing: 6) {
      Text(
        String(
          format: L10n.string("tag_settings_inspection_missing_title"),
          summary.missingPaths.count
        )
      )
      .font(.caption)
      .foregroundColor(.secondary)

      ForEach(preview, id: \.self) { path in
        Label(path, systemImage: "exclamationmark.triangle")
          .font(.caption2)
          .lineLimit(1)
          .foregroundColor(.secondary)
      }

      if summary.missingPaths.count > preview.count {
        Text(
          String(
            format: L10n.string("tag_settings_inspection_missing_more"),
            summary.missingPaths.count - preview.count
          )
        )
        .font(.caption2)
        .foregroundColor(.secondary)
      }
    }
  }

  private var inspectionDescription: String {
    let summary = tagService.lastInspection
    guard summary.checkedCount > 0 else {
      return L10n.string("tag_settings_inspection_never")
    }
    return String(
      format: L10n.string("tag_settings_inspection_description"),
      summary.checkedCount,
      summary.recoveredCount,
      summary.removedCount
    )
  }

  private func runInspectionNow() {
    guard !isInspecting else { return }
    Task { @MainActor in
      isInspecting = true
      await tagService.inspectNow()
      isInspecting = false
    }
  }

  @ViewBuilder
  /// 主列表：展示所有标签、支持单条操作
  private var tagListSection: some View {
    let height = listHeight
    ScrollView {
      VStack(spacing: 0) {
        ForEach(filteredTags) { tag in
          tagRow(for: tag)
          if tag.id != filteredTags.last?.id {
            Divider()
          }
        }
      }
      .padding(.vertical, 6)
      .background(
        RoundedRectangle(cornerRadius: 12, style: .continuous)
          .fill(.quaternary)
      )
      .padding(.horizontal, 2)
    }
    .frame(height: height)
    .scrollIndicators(.automatic)
  }

  private func tagRow(for tag: TagRecord) -> some View {
    HStack(alignment: .center, spacing: 12) {
      if batchMode {
        Toggle("", isOn: selectionBinding(for: tag))
          .toggleStyle(.checkbox)
          .labelsHidden()
      }
      VStack(alignment: .leading, spacing: 4) {
        Text(tag.name)
          .font(.headline)
        Text(
          String(
            format: L10n.string("tag_settings_usage_format"),
            tag.usageCount
          )
        )
        .font(.caption)
        .foregroundColor(.secondary)
      }
      Spacer()
      colorControl(for: tag)
      Button {
        editingTag = tag
      } label: {
        Label(L10n.string("tag_settings_rename_button"), systemImage: "pencil")
          .labelStyle(.iconOnly)
      }
      .buttonStyle(.borderless)
      .help(L10n.string("tag_settings_rename_button"))

      Button(role: .destructive) {
        deletingTag = tag
      } label: {
        Label(L10n.string("tag_settings_delete_button"), systemImage: "trash")
          .labelStyle(.iconOnly)
      }
      .buttonStyle(.borderless)
      .help(L10n.string("tag_settings_delete_button"))
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 8)
  }

  private var listHeight: CGFloat {
    let rowHeight: CGFloat = 56
    let totalHeight = CGFloat(filteredTags.count) * rowHeight + 12
    let maxHeight: CGFloat = 360
    return min(max(totalHeight, rowHeight * 2), maxHeight)
  }

  private var smartFilterList: some View {
    let filters = tagService.smartFilters
    let height = smartFilterListHeight(count: filters.count)
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
            smartFilterRow(for: filter)
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

  private func smartFilterListHeight(count: Int) -> CGFloat {
    let rowHeight: CGFloat = 56
    if count == 0 {
      return rowHeight * 2
    }
    let minHeight = rowHeight * min(CGFloat(count), 3)
    let totalHeight = CGFloat(count) * rowHeight + 12
    let maxHeight: CGFloat = 320
    return min(max(totalHeight, minHeight), maxHeight)
  }

  private func selectionBinding(for tag: TagRecord) -> Binding<Bool> {
    Binding(
      get: { selectedTagIDs.contains(tag.id) },
      set: { newValue in
        if newValue {
          selectedTagIDs.insert(tag.id)
        } else {
          selectedTagIDs.remove(tag.id)
        }
      }
    )
  }

  private func colorControl(for tag: TagRecord) -> some View {
    HStack(spacing: 8) {
      ColorPicker(
        L10n.string("tag_settings_color_picker_label"),
        selection: colorBinding(for: tag),
        supportsOpacity: false
      )
      .labelsHidden()
      .frame(width: 34)
      .help(L10n.string("tag_settings_color_picker_label"))

      if tag.colorHex != nil {
        Button {
          clearColor(for: tag)
        } label: {
          Image(systemName: "gobackward")
        }
        .buttonStyle(.borderless)
        .padding(.leading, 4)
        .help(L10n.string("tag_settings_color_clear_button"))
      }
    }
  }

  private func colorBinding(for tag: TagRecord) -> Binding<Color> {
    Binding(
      get: {
        if let cached = colorDrafts[tag.id] {
          return cached
        }
        return Color(hexString: tag.colorHex) ?? .accentColor
      },
      set: { newValue in
        colorDrafts[tag.id] = newValue
        Task {
          await tagService.updateColor(tagID: tag.id, hex: newValue.hexString())
          await MainActor.run {
            colorDrafts[tag.id] = nil
          }
        }
      }
    )
  }

  private func smartFilterRow(for filter: TagSmartFilter) -> some View {
    HStack(alignment: .center, spacing: 12) {
      VStack(alignment: .leading, spacing: 4) {
        Text(filter.name)
          .font(.headline)
          .lineLimit(1)
        let summary = smartFilterSummary(filter)
        if !summary.isEmpty {
          Text(summary)
            .font(.caption)
            .foregroundColor(.secondary)
        }
      }
      Spacer()
      Button {
        tagService.applySmartFilter(filter)
      } label: {
        Label(L10n.string("tag_settings_smart_filters_apply"), systemImage: "checkmark.circle")
          .labelStyle(.iconOnly)
      }
      .buttonStyle(.borderless)
      .help(L10n.string("tag_settings_smart_filters_apply"))

      Button {
        startRenamingSmartFilter(filter)
      } label: {
        Label(L10n.string("tag_settings_smart_filters_rename"), systemImage: "pencil")
          .labelStyle(.iconOnly)
      }
      .buttonStyle(.borderless)
      .help(L10n.string("tag_settings_smart_filters_rename"))

      Button(role: .destructive) {
        deletingSmartFilter = filter
      } label: {
        Label(L10n.string("tag_settings_smart_filters_delete"), systemImage: "trash")
          .labelStyle(.iconOnly)
      }
      .buttonStyle(.borderless)
      .help(L10n.string("tag_settings_smart_filters_delete"))
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 8)
  }

  private func smartFilterSummary(_ filter: TagSmartFilter) -> String {
    var parts: [String] = []
    let modeText = filterModeDescription(filter.filter.mode)
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

  /// 打开智能筛选命名弹窗，并预填原名称
  private func startRenamingSmartFilter(_ filter: TagSmartFilter) {
    smartFilterRenameText = filter.name
    renamingSmartFilter = filter
  }

  /// 将筛选模式转换为本地化字符串
  private func filterModeDescription(_ mode: TagFilterMode) -> String {
    switch mode {
    case .any:
      return L10n.string("tag_filter_mode_any")
    case .all:
      return L10n.string("tag_filter_mode_all")
    case .exclude:
      return L10n.string("tag_filter_mode_exclude")
    }
  }

  /// 方便在列表和批量操作中根据 ID 查找名称
  private var tagNameLookup: [Int64: String] {
    Dictionary(uniqueKeysWithValues: tagService.allTags.map { ($0.id, $0.name) })
  }

  /// 清除单个标签的颜色并刷新内存草稿
  private func clearColor(for tag: TagRecord) {
    colorDrafts[tag.id] = nil
    Task {
      await tagService.updateColor(tagID: tag.id, hex: nil)
    }
  }

  /// 把颜色选择器的值批量下发到选中标签
  private func applyBatchColor() {
    guard !selectedTagIDs.isEmpty else { return }
    let hex = batchColor.hexString()
    Task {
      await tagService.updateColor(tagIDs: selectedTagIDs, hex: hex)
    }
  }

  /// 批量恢复默认颜色
  private func clearBatchColor() {
    guard !selectedTagIDs.isEmpty else { return }
    Task {
      await tagService.updateColor(tagIDs: selectedTagIDs, hex: nil)
    }
  }

  /// 删除批量选择的标签，并重置模式
  private func performBatchDelete() {
    guard !selectedTagIDs.isEmpty else { return }
    let ids = selectedTagIDs
    Task {
      await tagService.deleteTags(ids)
      await MainActor.run {
        selectedTagIDs.removeAll()
        batchMode = false
        showingBatchDeleteConfirm = false
      }
    }
  }

  /// 清空选中标签的图片关联关系
  private func performClearAssignments() {
    guard !selectedTagIDs.isEmpty else { return }
    let ids = selectedTagIDs
    Task {
      await tagService.clearAssignments(for: ids)
      await MainActor.run {
        showingClearAssignmentsConfirm = false
      }
    }
  }

  /// 将选中标签合并到指定名称（可新建）
  private func performMerge(targetName: String) {
    guard !selectedTagIDs.isEmpty else { return }
    Task {
      await tagService.mergeTags(sourceIDs: selectedTagIDs, targetName: targetName)
      await MainActor.run {
        mergeTargetName = ""
        showingMergeSheet = false
        batchMode = false
        selectedTagIDs.removeAll()
      }
    }
  }
}

private struct TagRenameSheet: View {
  let tag: TagRecord
  let onSave: (String) -> Void

  @Environment(\.dismiss) private var dismiss
  @State private var name: String

  init(tag: TagRecord, onSave: @escaping (String) -> Void) {
    self.tag = tag
    self.onSave = onSave
    _name = State(initialValue: tag.name)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text(L10n.string("tag_settings_rename_title"))
        .font(.headline)

      TextField(L10n.string("tag_settings_rename_placeholder"), text: $name)
        .textFieldStyle(.roundedBorder)
        .onSubmit(save)

      HStack {
        Spacer()
        Button(L10n.key("cancel_button")) { dismiss() }
        Button(L10n.key("save_button")) { save() }
          .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
      }
    }
    .padding()
    .frame(minWidth: 320)
  }

  private func save() {
    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return }
    onSave(trimmed)
    dismiss()
  }
}

private struct TagBatchAddSheet: View {
  @Binding var text: String
  let onSubmit: ([String]) -> Void
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text(L10n.string("tag_settings_batch_add_title"))
        .font(.headline)
      Text(L10n.string("tag_settings_batch_add_hint"))
        .font(.caption)
        .foregroundColor(.secondary)

      TextEditor(text: $text)
        .font(.body)
        .frame(minHeight: 120)
        .overlay(
          RoundedRectangle(cornerRadius: 8)
            .stroke(Color.secondary.opacity(0.2))
        )

      HStack {
        Spacer()
        Button(L10n.key("cancel_button")) { dismiss() }
        Button(L10n.key("save_button")) {
          let names = text
            .components(separatedBy: CharacterSet(charactersIn: ",;\n"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
          onSubmit(names)
          text = ""
          dismiss()
        }
        .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
      }
    }
    .padding()
    .frame(minWidth: 360)
  }
}

private struct TagMergeSheet: View {
  @Binding var mergeTarget: String
  let selectedCount: Int
  let onSubmit: (String) -> Void
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text(String(format: L10n.string("tag_settings_merge_title"), selectedCount))
        .font(.headline)
      Text(L10n.string("tag_settings_merge_hint"))
        .font(.caption)
        .foregroundColor(.secondary)

      TextField(L10n.string("tag_settings_merge_placeholder"), text: $mergeTarget)
        .textFieldStyle(.roundedBorder)
        .onSubmit(submit)

      HStack {
        Spacer()
        Button(L10n.key("cancel_button")) { dismiss() }
        Button(L10n.key("save_button")) { submit() }
          .disabled(mergeTarget.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
      }
    }
    .padding()
    .frame(minWidth: 320)
  }

  private func submit() {
    let trimmed = mergeTarget.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return }
    onSubmit(trimmed)
    dismiss()
  }
}

private extension TagSettingsView {
  var filteredTags: [TagRecord] {
    let base = tagService.allTags
    let keyword = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !keyword.isEmpty else { return base }
    return base.filter { tag in
      tag.name.localizedCaseInsensitiveContains(keyword)
    }
  }

  var totalTags: Int {
    tagService.allTags.count
  }

  var usedTags: Int {
    tagService.allTags.filter { $0.usageCount > 0 }.count
  }

  var unusedTags: Int {
    max(0, totalTags - usedTags)
  }

  func statColumn(title: String, value: Int) -> some View {
    VStack {
      Text("\(value)")
        .font(.title3.bold())
      Text(title)
        .font(.caption)
        .foregroundColor(.secondary)
    }
    .frame(maxWidth: .infinity)
  }
}
