//
//  TagSettingsView.swift
//
//  Created by Eric Cai on 2025/11/08.
//

import SwiftUI

struct TagSettingsView: View {
  @ObservedObject private var tagService: TagService
  @StateObject private var store: TagSettingsStore
  @ObservedObject private var localizationManager = LocalizationManager.shared

  init(tagService: TagService) {
    _tagService = ObservedObject(wrappedValue: tagService)
    _store = StateObject(wrappedValue: TagSettingsStore(tagService: tagService))
  }

  // MARK: - 视图状态
  @State private var editingTag: TagRecord?
  @State private var deletingTag: TagRecord?
  @State private var isInspecting = false
  // 批量新增弹窗
  @State private var showingBatchAddSheet = false
  @State private var showingCleanupConfirm = false
  @State private var batchAddInput: String = ""
  // 智能筛选命名/删除状态
  @State private var renamingSmartFilter: TagSmartFilter?
  @State private var smartFilterRenameText: String = ""
  @State private var deletingSmartFilter: TagSmartFilter?
  @State private var dismissedFeedbackID: TagOperationFeedback.ID?
  @State private var showingFeedbackHistory = false
  @State private var showingTelemetry = false

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      feedbackBanner
      TagInspectionCard(
        summary: tagService.lastInspection,
        isInspecting: isInspecting,
        descriptionText: inspectionDescription,
        onInspect: runInspectionNow
      )
      TagStatsCard(
        total: totalTags,
        used: usedTags,
        unused: unusedTags
      )
      smartFilterPanel
      tagManagementSurface

      HStack(spacing: 12) {
        Button {
          showingCleanupConfirm = true
        } label: {
          Label(L10n.string("tag_settings_cleanup_button"), systemImage: "trash.slash")
        }

        Spacer()

        Button {
          Task { await tagService.refreshAllTags(immediate: true) }
        } label: {
          Label(L10n.string("tag_settings_refresh_button"), systemImage: "arrow.clockwise.circle")
        }
#if DEBUG
        Button {
          showingTelemetry = true
        } label: {
          Label("推荐统计", systemImage: "chart.bar")
        }
#endif
      }
    }
    .settingsContentContainer()
    .onDisappear { store.teardown() }
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
    .sheet(isPresented: $store.isShowingMergeSheet) {
      TagMergeSheet(
        mergeTarget: $store.mergeTargetName,
        selectedCount: store.selectedTagIDs.count
      ) { target in
        store.performMerge(targetName: target)
      }
    }
    .sheet(item: $renamingSmartFilter) { filter in
      SmartFilterNameSheet(
        name: $smartFilterRenameText,
        titleKey: "tag_settings_smart_sheet_title",
        placeholderKey: "tag_filter_smart_sheet_placeholder",
        actionKey: "tag_settings_smart_sheet_save_button"
      ) { newName in
        try tagService.renameSmartFilter(id: filter.id, to: newName)
        renamingSmartFilter = nil
      }
      .frame(width: 320)
    }
    .sheet(isPresented: $showingTelemetry) {
      TagRecommendationDebugView(
        allTags: tagService.allTags,
        dismiss: { showingTelemetry = false }
      )
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
      isPresented: $store.isShowingClearAssignmentsConfirm,
      titleVisibility: .visible
    ) {
      Button(L10n.string("tag_settings_clear_assignments_button"), role: .destructive) {
        store.performClearAssignments()
      }
      Button(L10n.key("cancel_button"), role: .cancel) {
        store.isShowingClearAssignmentsConfirm = false
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
      isPresented: $store.isShowingDeleteConfirm,
      titleVisibility: .visible
    ) {
      Button(L10n.string("tag_settings_batch_delete_button"), role: .destructive) {
        store.performBatchDelete()
      }
      Button(L10n.key("cancel_button"), role: .cancel) {
        store.isShowingDeleteConfirm = false
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
      store.pruneSelection(availableIDs: existingIDs)
      store.pruneColorDrafts(using: tags)
    }
    .onAppear {
      if store.isBatchModeEnabled {
        store.isBatchPanelExpanded = true
      }
    }
    .onChange(of: store.isBatchModeEnabled) { _, newValue in
      withAnimation(SettingsAnimations.collapse) {
        store.isBatchPanelExpanded = newValue
      }
    }
  }

  @ViewBuilder
  private var feedbackBanner: some View {
    if tagService.feedbackEvent != nil || !tagService.feedbackHistory.isEmpty {
      HStack(alignment: .center, spacing: 12) {
        if let feedback = tagService.feedbackEvent,
           dismissedFeedbackID != feedback.id {
          TagFeedbackBanner(feedback: feedback) {
            withAnimation(.easeOut(duration: 0.2)) {
              dismissedFeedbackID = feedback.id
            }
          }
          .transition(.move(edge: .top).combined(with: .opacity))
        }
        Spacer(minLength: 8)
        if !tagService.feedbackHistory.isEmpty {
          Button {
            showingFeedbackHistory = true
          } label: {
            Label(L10n.string("tag_settings_feedback_history_button"), systemImage: "clock.arrow.circlepath")
          }
          .buttonStyle(.borderless)
        }
      }
      .sheet(isPresented: $showingFeedbackHistory) {
        FeedbackHistorySheet(
          feedbacks: tagService.feedbackHistory,
          dismiss: { showingFeedbackHistory = false }
        )
        .frame(minWidth: 360, minHeight: 320)
      }
    }
  }

  /// 智能筛选面板，保持可折叠
  private var smartFilterPanel: some View {
    CollapsibleToolSection(
      title: L10n.string("tag_settings_smart_filters_title"),
      summary: smartFilterSummary,
      iconName: "line.3.horizontal.decrease.circle",
      isExpanded: $store.isSmartPanelExpanded,
      appearance: .grouped
    ) {
      smartFilterCard
    }
  }

  /// 标签管理主区域：包含批量工具、搜索与列表
  private var tagManagementSurface: some View {
    let inset: CGFloat = 16
    return VStack(spacing: 0) {
      VStack(alignment: .leading, spacing: 4) {
        Text(L10n.string("tag_settings_tools_section_title"))
          .font(.title3.bold())
        Text(L10n.string("tag_settings_tools_section_subtitle"))
          .font(.caption)
          .foregroundColor(.secondary)
      }
      .padding(.horizontal, inset)
      .padding(.top, inset)

      CollapsibleToolSection(
        title: L10n.string("tag_settings_batch_mode_toggle"),
        summary: batchToolsSummary,
        iconName: "square.stack.3d.up",
        isExpanded: $store.isBatchPanelExpanded,
        appearance: .embedded,
        trailing: {
          HStack(spacing: 12) {
            Button(action: onShowBatchAddSheet) {
              Label(L10n.string("tag_settings_batch_add_button"), systemImage: "plus.circle")
                .labelStyle(.titleAndIcon)
            }
            .buttonStyle(.borderless)
            .help(L10n.string("tag_settings_batch_add_button"))

            Spacer(minLength: 8)

            Toggle(L10n.string("tag_settings_batch_toggle_short"), isOn: $store.isBatchModeEnabled)
          }
        }
      ) {
        TagBatchControlsView(
          store: store,
          onShowBatchAddSheet: onShowBatchAddSheet,
          showsHeader: false
        )
      }
      .padding(.horizontal, inset)
      .padding(.bottom, 8)

      Divider()
        .padding(.horizontal, inset)

      searchField
        .padding(.horizontal, inset)
        .padding(.vertical, 12)

      Divider()
        .padding(.horizontal, inset)

      tagContentSection
        .padding(.horizontal, inset)
        .padding(.vertical, 12)
    }
    .background(
      RoundedRectangle(cornerRadius: 18, style: .continuous)
        .fill(Color(.windowBackgroundColor))
    )
    .overlay(
      RoundedRectangle(cornerRadius: 18, style: .continuous)
        .stroke(Color.secondary.opacity(0.15))
    )
  }

  private func onShowBatchAddSheet() {
    showingBatchAddSheet = true
  }

  /// 智能筛选列表与操作入口
  private var smartFilterCard: some View {
    TagSmartFilterSection(
      filters: tagService.smartFilters,
      tagNameLookup: tagNameLookup,
      activeFilterID: activeSmartFilterID,
      onApply: { tagService.applySmartFilter($0) },
      onRename: { startRenamingSmartFilter($0) },
      onDelete: { deletingSmartFilter = $0 },
      showsContainer: false,
      showsTitle: false
    )
  }

  /// 顶部搜索框，支持清空按钮
  private var searchField: some View {
    let binding = store.searchBinding
    return HStack {
      Image(systemName: "magnifyingglass")
        .foregroundColor(.secondary)
      TextField(L10n.string("tag_settings_search_placeholder"), text: binding)
        .textFieldStyle(.plain)
        .autocorrectionDisabled()
      if !binding.wrappedValue.isEmpty {
        Button {
          binding.wrappedValue = ""
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

  @ViewBuilder
  private var tagContentSection: some View {
    if tagService.allTags.isEmpty {
      TagEmptyStateView(
        systemImage: "tray",
        message: L10n.string("tag_settings_empty")
      )
      .frame(minHeight: 220)
      .frame(maxWidth: .infinity)
      Text(L10n.string("tag_settings_empty_hint"))
        .font(.caption)
        .foregroundColor(.secondary)
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.top, 8)
    } else if filteredTags.isEmpty {
      TagEmptyStateView(
        systemImage: "magnifyingglass",
        message: L10n.string("tag_settings_search_empty"),
        minHeight: 160
      )
      .frame(maxWidth: .infinity)
      Text(L10n.string("tag_settings_search_hint"))
        .font(.caption)
        .foregroundColor(.secondary)
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.top, 8)
    } else {
      tagListSection(embedInContainer: true)
        .frame(maxWidth: .infinity)
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
  private func tagListSection(embedInContainer: Bool) -> some View {
    let tags = filteredTags
    let height = listHeight(for: tags.count)
    ScrollView {
      LazyVStack(spacing: 0) {
        ForEach(tags) { tag in
          TagManagementRow(
            tag: tag,
            isBatchMode: store.isBatchModeEnabled,
            selectionBinding: store.isBatchModeEnabled ? store.selectionBinding(for: tag.id) : nil,
            usageText: tagUsageSummary(for: tag.usageCount),
            colorBinding: store.colorBinding(for: tag),
            canClearColor: store.canClearColor(for: tag),
            onClearColor: { store.clearColor(for: tag) },
            onRename: { editingTag = tag },
            onDelete: { deletingTag = tag }
          )
          if tag.id != tags.last?.id {
            Divider()
          }
        }
      }
      .padding(.vertical, embedInContainer ? 0 : 6)
      .background(
        Group {
          if !embedInContainer {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
              .fill(.quaternary)
          }
        }
      )
      .padding(.horizontal, embedInContainer ? 0 : 2)
    }
    .frame(height: height)
    .scrollIndicators(.automatic)
  }

  private func listHeight(for count: Int) -> CGFloat {
    let rowHeight: CGFloat = 56
    let totalHeight = CGFloat(count) * rowHeight + 12
    let maxHeight: CGFloat = 360
    return min(max(totalHeight, rowHeight * 2), maxHeight)
  }

  private func tagUsageSummary(for count: Int) -> String {
    String(format: L10n.string("tag_usage_format"), count)
  }

  private var smartFilterSummary: String {
    if tagService.smartFilters.isEmpty {
      return L10n.string("tag_settings_smart_filters_empty")
    }
    if let activeName = activeSmartFilterName {
      return String(
        format: L10n.string("tag_settings_smart_summary_active"),
        activeName
      )
    }
    return String(
      format: L10n.string("tag_settings_smart_summary_count"),
      tagService.smartFilters.count
    )
  }

  private var batchToolsSummary: String {
    if store.isBatchModeEnabled {
      return String(
        format: L10n.string("tag_settings_batch_selection_count"),
        store.selectedTagIDs.count
      )
    }
    return L10n.string("tag_settings_batch_disabled_summary")
  }

  /// 打开智能筛选命名弹窗，并预填原名称
  private func startRenamingSmartFilter(_ filter: TagSmartFilter) {
    smartFilterRenameText = filter.name
    renamingSmartFilter = filter
  }

  private var activeSmartFilterID: TagSmartFilter.ID? {
    tagService.smartFilters.first(where: { $0.filter == tagService.activeFilter })?.id
  }

  private var activeSmartFilterName: String? {
    guard let activeSmartFilterID else { return nil }
    return tagService.smartFilters.first(where: { $0.id == activeSmartFilterID })?.name
  }

  /// 方便在列表和批量操作中根据 ID 查找名称
  private var tagNameLookup: [Int64: String] {
    Dictionary(uniqueKeysWithValues: tagService.allTags.map { ($0.id, $0.name) })
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

private struct FeedbackHistorySheet: View {
  let feedbacks: [TagOperationFeedback]
  let dismiss: () -> Void

  var body: some View {
    NavigationStack {
      List(feedbacks) { feedback in
        VStack(alignment: .leading, spacing: 4) {
          HStack(spacing: 6) {
            Image(systemName: feedback.isSuccess ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
              .foregroundColor(feedback.isSuccess ? .green : .orange)
            Text(feedback.message)
              .font(.subheadline)
          }
          Text(localizedTimestamp(for: feedback))
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
      }
      .navigationTitle(L10n.string("tag_settings_feedback_history_title"))
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button(L10n.string("tag_settings_feedback_history_close")) { dismiss() }
        }
      }
    }
  }

  private func localizedTimestamp(for feedback: TagOperationFeedback) -> String {
    LocalizedDateFormatter.shortTimestamp(for: feedback.timestamp)
  }
}

enum SettingsAnimations {
  static let collapse = Animation.spring(
    response: 0.24,
    dampingFraction: 0.92,
    blendDuration: 0.08
  )
}

private struct CollapsibleToolSection<Content: View, Trailing: View>: View {
  enum Appearance {
    case grouped
    case embedded

    var contentInsets: EdgeInsets {
      switch self {
      case .grouped:
        return EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12)
      case .embedded:
        return EdgeInsets(top: 12, leading: 0, bottom: 0, trailing: 0)
      }
    }
  }

  let title: String
  let summary: String
  let iconName: String
  @Binding var isExpanded: Bool
  let appearance: Appearance
  let trailing: () -> Trailing
  let content: () -> Content
  let animation: Animation

  init(
    title: String,
    summary: String,
    iconName: String,
    isExpanded: Binding<Bool>,
    appearance: Appearance = .grouped,
    animation: Animation = SettingsAnimations.collapse,
    @ViewBuilder trailing: @escaping () -> Trailing,
    @ViewBuilder content: @escaping () -> Content
  ) {
    self.title = title
    self.summary = summary
    self.iconName = iconName
    _isExpanded = isExpanded
    self.appearance = appearance
    self.animation = animation
    self.trailing = trailing
    self.content = content
  }

  init(
    title: String,
    summary: String,
    iconName: String,
    isExpanded: Binding<Bool>,
    appearance: Appearance = .grouped,
    animation: Animation = SettingsAnimations.collapse,
    @ViewBuilder content: @escaping () -> Content
  ) where Trailing == EmptyView {
    self.init(
      title: title,
      summary: summary,
      iconName: iconName,
      isExpanded: isExpanded,
      appearance: appearance,
      animation: animation,
      trailing: { EmptyView() },
      content: content
    )
  }

  var body: some View {
    container
      .animation(animation, value: isExpanded)
  }

  private var container: some View {
    Group {
      if appearance == .grouped {
        GroupBox {
          innerStack
        }
      } else {
        innerStack
      }
    }
  }

  private var header: some View {
    HStack(alignment: .center, spacing: 8) {
      Button {
        withAnimation(animation) {
          isExpanded.toggle()
        }
      } label: {
        HStack(alignment: .center, spacing: 8) {
          Image(systemName: iconName)
            .font(.headline)
          VStack(alignment: .leading, spacing: 2) {
            Text(title)
              .font(.headline)
            Text(summary)
              .font(.caption)
              .foregroundColor(.secondary)
              .lineLimit(1)
          }
          Spacer(minLength: 8)
          Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
            .foregroundColor(.secondary)
        }
      }
      .buttonStyle(.plain)

      trailing()
    }
  }

  private var innerStack: some View {
    VStack(alignment: .leading, spacing: 10) {
      header
      contentWrapper
    }
    .padding(appearance.contentInsets)
  }

  private var contentWrapper: some View {
    VStack(alignment: .leading, spacing: 0) {
      content()
        .opacity(isExpanded ? 1 : 0)
        .animation(animation, value: isExpanded)
    }
    .frame(maxHeight: isExpanded ? .none : 0, alignment: .top)
    .clipped()
  }
}

private extension TagSettingsView {
  var filteredTags: [TagRecord] {
    let base = tagService.allTagsSortedByName
    let keyword = store.debouncedSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
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
}
