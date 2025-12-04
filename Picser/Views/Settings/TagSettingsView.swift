//
//  TagSettingsView.swift
//
//  标签设置视图
//  在设置页面显示的标签管理界面，提供完整的标签管理、批量操作、智能筛选器管理等功能。
//
//  Created by Eric Cai on 2025/11/08.
//

import SwiftUI

/// 标签设置视图
///
/// 应用设置页面的标签管理界面，提供全面的标签管理功能。
///
/// 核心功能：
/// 1. **标签巡检**：检查图片文件有效性，恢复或清理失效记录
/// 2. **标签统计**：显示标签总数、已使用、未使用的统计信息
/// 3. **智能筛选器管理**：查看、重命名、删除智能筛选器
/// 4. **批量操作**：批量选择、删除、合并、清空标签
/// 5. **单标签操作**：重命名、删除、修改颜色
/// 6. **搜索筛选**：按名称搜索标签
/// 7. **批量添加**：通过文本批量创建标签
/// 8. **操作反馈**：显示操作结果和历史记录
///
/// 设计特点：
/// - **折叠面板**：智能筛选器和批量工具可折叠，节省空间
/// - **实时搜索**：防抖搜索，避免高频更新
/// - **批量模式**：切换批量操作模式，多选标签
/// - **颜色管理**：每个标签支持自定义颜色
/// - **确认对话框**：危险操作需要用户确认
/// - **反馈横幅**：显示操作成功/失败的反馈信息
///
/// 数据管理：
/// - **TagService**：标签服务，提供数据和操作接口
/// - **TagSettingsStore**：设置页面的状态管理，处理批量操作、搜索等
///
/// 状态管理：
/// - **editingTag**：正在重命名的标签
/// - **deletingTag**：正在删除的标签
/// - **renamingSmartFilter**：正在重命名的智能筛选器
/// - **deletingSmartFilter**：正在删除的智能筛选器
/// - **showingBatchAddSheet**：批量添加弹窗显示状态
/// - **showingCleanupConfirm**：清理未使用标签确认对话框
/// - **showingFeedbackHistory**：操作历史记录弹窗
///
/// 交互流程：
/// 1. 用户查看标签统计和智能筛选器
/// 2. 开启批量模式，多选标签
/// 3. 执行批量操作（删除、合并、清空关联）
/// 4. 或者对单个标签进行操作（重命名、删除、改颜色）
/// 5. 查看操作反馈和历史记录
///
/// 使用场景：
/// - 用户需要管理大量标签
/// - 清理和整理标签系统
/// - 批量操作提高效率
/// - 检查和修复数据完整性
struct TagSettingsView: View {
  /// 标签服务，提供标签数据和操作接口
  @ObservedObject private var tagService: TagService

  /// 设置页面状态管理器
  ///
  /// 管理批量操作、搜索、颜色编辑等状态。
  @StateObject private var store: TagSettingsStore

  /// 本地化管理器，监听语言切换
  @ObservedObject private var localizationManager = LocalizationManager.shared

  /// 初始化标签设置视图
  ///
  /// - Parameter tagService: 标签服务实例
  init(tagService: TagService) {
    _tagService = ObservedObject(wrappedValue: tagService)
    _store = StateObject(wrappedValue: TagSettingsStore(tagService: tagService))
  }

  // MARK: - 视图状态

  /// 正在重命名的标签
  /// 非 nil 时显示重命名弹窗
  @State private var editingTag: TagRecord?

  /// 正在删除的标签
  /// 非 nil 时显示删除确认对话框
  @State private var deletingTag: TagRecord?

  /// 巡检进行中标志
  /// true 时禁用巡检按钮，防止重复触发
  @State private var isInspecting = false

  // 批量新增弹窗

  /// 批量添加弹窗显示状态
  @State private var showingBatchAddSheet = false

  /// 清理未使用标签确认对话框显示状态
  @State private var showingCleanupConfirm = false

  /// 批量添加文本输入内容
  /// 用户在弹窗中输入的标签名称列表
  @State private var batchAddInput: String = ""

  // 智能筛选命名/删除状态

  /// 正在重命名的智能筛选器
  /// 非 nil 时显示重命名弹窗
  @State private var renamingSmartFilter: TagSmartFilter?

  /// 智能筛选器重命名文本输入
  /// 用户在重命名弹窗中输入的新名称
  @State private var smartFilterRenameText: String = ""

  /// 正在删除的智能筛选器
  /// 非 nil 时显示删除确认对话框
  @State private var deletingSmartFilter: TagSmartFilter?

  /// 已关闭的反馈横幅 ID
  /// 用于记住用户已手动关闭的反馈，避免重复显示
  @State private var dismissedFeedbackID: TagOperationFeedback.ID?

  /// 操作历史记录弹窗显示状态
  @State private var showingFeedbackHistory = false



  /// 主视图布局
  ///
  /// 垂直排列的设置页面内容，包含多个功能区域。
  ///
  /// 布局结构（从上到下）：
  /// 1. **feedbackBanner**：操作反馈横幅，显示最新的操作结果
  /// 2. **TagInspectionCard**：巡检卡片，显示巡检结果和触发按钮
  /// 3. **TagStatsCard**：统计卡片，显示标签总数、已使用、未使用
  /// 4. **smartFilterPanel**：智能筛选器管理面板（可折叠）
  /// 5. **tagManagementSurface**：标签管理主区域，包含批量工具、搜索、列表
  /// 6. **底部按钮行**：清理未使用标签、刷新
  ///
  /// 修饰符和交互：
  /// - **settingsContentContainer()**：应用设置页面的标准容器样式
  /// - **onDisappear**：离开页面时清理 store 状态
  /// - **sheet**：多个弹窗（重命名、批量添加、合并）
  /// - **alert**：删除标签确认对话框
  /// - **confirmationDialog**：危险操作确认（清空关联、清理未使用、批量删除、删除智能筛选器）
  /// - **onChange**：监听标签列表变化，清理无效的选择和颜色草稿
  /// - **onAppear**：初始化批量面板展开状态
  ///
  /// 状态同步：
  /// - 标签列表变化时，清理失效的选择项和颜色编辑草稿
  /// - 批量模式切换时，自动展开/折叠批量工具面板
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

      }
    }
    .settingsContentContainer()
    .onDisappear { store.teardown() }
    // MARK: - 弹窗修饰符
    /// 标签重命名弹窗
    /// 绑定到 editingTag 状态，非 nil 时显示
    .sheet(item: $editingTag) { tag in
      TagRenameSheet(tag: tag) { newName in
        Task { await tagService.rename(tagID: tag.id, to: newName) }
      }
    }
    /// 批量添加标签弹窗
    /// 用户可以输入多个标签名称，用逗号、分号或换行符分隔
    .sheet(isPresented: $showingBatchAddSheet) {
      TagBatchAddSheet(text: $batchAddInput) { names in
        Task { await tagService.addTags(names: names) }
      }
    }
    /// 标签合并弹窗
    /// 将多个选中的标签合并为一个目标标签
    .sheet(isPresented: $store.isShowingMergeSheet) {
      TagMergeSheet(
        mergeTarget: $store.mergeTargetName,
        selectedCount: store.selectedTagIDs.count
      ) { target in
        store.performMerge(targetName: target)
      }
    }
    /// 智能筛选器重命名弹窗
    /// 绑定到 renamingSmartFilter 状态
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

    // MARK: - 确认对话框修饰符
    /// 删除单个标签的确认对话框
    /// 显示标签名称和使用次数，警告用户操作不可逆
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
    /// 清空标签关联的确认对话框
    /// 移除选中标签的所有图片关联，但保留标签本身
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
    /// 清理未使用标签的确认对话框
    /// 删除所有没有图片关联的孤立标签
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
    /// 批量删除标签的确认对话框
    /// 永久删除选中的多个标签及其所有关联
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
    } message: {
      let names = store.selectedTagNames
      let displayedNames = names.prefix(5).joined(separator: ", ")
      let remaining = names.count - 5
      if remaining > 0 {
        Text(String(
          format: L10n.string("tag_settings_batch_delete_message_more"),
          displayedNames,
          remaining
        ))
      } else {
        Text(String(
          format: L10n.string("tag_settings_batch_delete_message"),
          displayedNames
        ))
      }
    }
    /// 删除智能筛选器的确认对话框
    /// 显示智能筛选器名称，警告用户操作不可逆
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
    // MARK: - 状态变化监听
    /// 监听全局标签列表变化
    ///
    /// 当标签被删除或修改时：
    /// 1. 清理失效的批量选择项（pruneSelection）
    /// 2. 清理无效的颜色编辑草稿（pruneColorDrafts）
    ///
    /// 确保 UI 状态与数据一致，避免操作不存在的标签。
    .onChange(of: tagService.allTags) { _, tags in
      let existingIDs = Set(tags.map(\.id))
      store.pruneSelection(availableIDs: existingIDs)
      store.pruneColorDrafts(using: tags)
    }
    /// 视图首次显示时初始化批量面板状态
    ///
    /// 如果批量模式已开启，自动展开批量工具面板。
    .onAppear {
      if store.isBatchModeEnabled {
        store.isBatchPanelExpanded = true
      }
    }
    /// 监听批量模式开关变化
    ///
    /// 自动展开或折叠批量工具面板，使用动画平滑过渡。
    .onChange(of: store.isBatchModeEnabled) { _, newValue in
      withAnimation(SettingsAnimations.collapse) {
        store.isBatchPanelExpanded = newValue
      }
    }
  }

  /// 操作反馈横幅
  ///
  /// 显示最新的操作结果反馈和历史记录入口。
  ///
  /// 显示条件：
  /// - 有新的反馈事件（feedbackEvent != nil）
  /// - 或者有历史记录（feedbackHistory 非空）
  ///
  /// 布局结构：
  /// 1. **TagFeedbackBanner**：显示最新的反馈消息
  ///    - 只有在未被用户手动关闭时显示（dismissedFeedbackID != feedback.id）
  ///    - 带有过渡动画（move + opacity）
  /// 2. **历史记录按钮**：点击查看所有操作历史
  ///    - 只在有历史记录时显示
  ///    - 打开 FeedbackHistorySheet 弹窗
  ///
  /// 交互功能：
  /// - 用户可以手动关闭当前反馈（点击关闭按钮）
  /// - 点击历史按钮查看所有操作记录
  ///
  /// 视觉设计：
  /// - 反馈横幅和历史按钮水平排列
  /// - 使用动画提升用户体验
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

  /// 智能筛选器管理面板
  ///
  /// 显示所有保存的智能筛选器，支持查看、重命名、删除操作。
  ///
  /// 设计特点：
  /// - **可折叠面板**：使用 CollapsibleToolSection 实现折叠/展开
  /// - **grouped 外观**：独立的卡片样式，带有背景和边框
  /// - **动态摘要**：根据智能筛选器的数量和激活状态生成摘要文本
  ///
  /// 面板内容：
  /// - **smartFilterCard**：智能筛选器列表视图
  ///   - 显示所有智能筛选器的名称
  ///   - 支持点击应用筛选器
  ///   - 支持重命名和删除操作
  ///   - 高亮当前激活的筛选器
  ///
  /// 展开状态：
  /// - 绑定到 store.isSmartPanelExpanded
  /// - 用户可以手动展开/折叠
  ///
  /// 使用场景：
  /// - 用户查看已保存的智能筛选器
  /// - 快速应用常用的筛选条件组合
  /// - 管理智能筛选器（重命名、删除）
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

  /// 标签管理主区域
  ///
  /// 集成批量工具、搜索和标签列表的综合管理界面。
  ///
  /// 设计特点：
  /// - **统一容器**：使用圆角矩形背景，视觉上独立于其他区域
  /// - **垂直布局**：从上到下依次排列各个功能模块
  /// - **内边距一致**：所有内容使用统一的 16pt 水平内边距
  ///
  /// 布局结构（从上到下）：
  /// 1. **顶部标题区域**：
  ///    - 主标题："工具和标签列表"
  ///    - 副标题：功能说明文本
  /// 2. **批量工具面板**（CollapsibleToolSection）：
  ///    - 折叠/展开的批量操作工具
  ///    - 标题行包含批量模式开关
  ///    - 展开时显示批量操作按钮（删除、合并、清空关联）
  /// 3. **分隔线**：视觉分隔批量工具和搜索区域
  /// 4. **搜索框**：按标签名称搜索
  /// 5. **分隔线**：视觉分隔搜索和列表区域
  /// 6. **标签列表**：显示所有标签（支持筛选和批量选择）
  ///
  /// 视觉设计：
  /// - **背景**：系统窗口背景色（.windowBackgroundColor）
  /// - **圆角**：18pt 连续曲线圆角
  /// - **边框**：半透明次要色边框（0.15 透明度）
  ///
  /// 交互功能：
  /// - 批量模式切换：开启/关闭批量选择
  /// - 搜索筛选：实时搜索标签名称
  /// - 标签选择：在批量模式下多选标签
  /// - 批量操作：对选中的标签执行批量操作
  ///
  /// 使用场景：
  /// - 用户需要查找和管理大量标签
  /// - 批量整理和清理标签系统
  /// - 快速定位特定标签
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

  /// 显示批量添加标签弹窗
  ///
  /// 设置 showingBatchAddSheet 状态为 true，触发弹窗显示。
  ///
  /// 调用时机：
  /// - 用户点击批量添加按钮
  /// - TagBatchControlsView 中的批量添加入口
  private func onShowBatchAddSheet() {
    showingBatchAddSheet = true
  }

  /// 智能筛选器列表视图
  ///
  /// 显示所有智能筛选器，并提供应用、重命名、删除操作。
  ///
  /// 功能特点：
  /// - **筛选器列表**：显示所有保存的智能筛选器
  /// - **应用筛选**：点击筛选器应用其条件
  /// - **重命名**：长按或右键菜单重命名筛选器
  /// - **删除**：长按或右键菜单删除筛选器
  /// - **高亮激活**：当前激活的筛选器高亮显示
  ///
  /// 数据来源：
  /// - **filters**：tagService.smartFilters（所有智能筛选器）
  /// - **tagNameLookup**：标签 ID 到名称的映射
  /// - **activeFilterID**：当前激活的智能筛选器 ID
  ///
  /// 视觉设计：
  /// - **无容器**：showsContainer = false，直接嵌入到父容器
  /// - **无标题**：showsTitle = false，标题由外层 CollapsibleToolSection 提供
  ///
  /// 使用场景：
  /// - 用户查看和管理已保存的智能筛选器
  /// - 快速应用常用的筛选条件
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

  /// 标签搜索框
  ///
  /// 顶部搜索输入框，支持按标签名称实时筛选。
  ///
  /// 功能特点：
  /// - **实时搜索**：输入变化立即更新筛选结果
  /// - **清空按钮**：输入非空时显示清空按钮
  /// - **防抖搜索**：store 内部使用防抖机制，避免高频更新
  ///
  /// 布局结构：
  /// - **搜索图标**：左侧放大镜图标
  /// - **文本输入框**：中间输入区域
  /// - **清空按钮**：右侧 X 图标（输入非空时显示）
  ///
  /// 数据绑定：
  /// - 使用 store.searchBinding 双向绑定搜索文本
  /// - store 内部处理防抖和筛选逻辑
  ///
  /// 视觉设计：
  /// - **背景**：半透明次要色背景（0.12 透明度）
  /// - **圆角**：10pt 圆角矩形
  /// - **内边距**：8pt 内边距
  ///
  /// 交互功能：
  /// - 输入文本：触发实时搜索
  /// - 点击清空按钮：清空输入并显示所有标签
  /// - 自动禁用拼写纠正
  ///
  /// 使用场景：
  /// - 用户在大量标签中快速定位
  /// - 按名称筛选标签列表
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

  /// 标签内容区域
  ///
  /// 根据标签数据状态显示不同的内容。
  ///
  /// 显示逻辑（优先级从高到低）：
  /// 1. **全局标签为空**：显示空状态提示
  ///    - 提示信息：暂无标签，引导用户创建
  ///    - 提示文本：如何添加标签的说明
  /// 2. **筛选结果为空**：显示搜索无结果提示
  ///    - 提示信息：未找到匹配的标签
  ///    - 提示文本：建议修改搜索关键词
  /// 3. **有筛选结果**：显示标签列表
  ///    - tagListSection：可滚动的标签列表
  ///    - 支持批量选择和单标签操作
  ///
  /// 空状态设计：
  /// - **图标**：使用 SF Symbol 图标（tray 或 magnifyingglass）
  /// - **消息**：本地化的提示文本
  /// - **提示**：副标题，说明如何解决当前状态
  /// - **最小高度**：确保视觉一致性
  ///
  /// 使用场景：
  /// - 初次使用，还没有创建任何标签
  /// - 搜索关键词没有匹配结果
  /// - 正常浏览和管理标签列表
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

  /// 巡检描述文本
  ///
  /// 根据最近一次巡检结果生成描述文本。
  ///
  /// 显示内容：
  /// - **从未巡检**：显示"尚未执行巡检"
  /// - **已巡检**：显示统计摘要
  ///   - 格式：检查了 N 张图片，恢复了 M 张，移除了 K 条记录
  ///
  /// 数据来源：
  /// - tagService.lastInspection（最近一次巡检摘要）
  ///   - checkedCount：检查的图片数量
  ///   - recoveredCount：通过书签恢复的图片数量
  ///   - removedCount：移除的无效记录数量
  ///
  /// 使用场景：
  /// - TagInspectionCard 显示巡检结果
  /// - 用户查看数据库健康状态
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

  /// 执行巡检操作
  ///
  /// 触发数据库完整性巡检，检查图片记录的有效性。
  ///
  /// 执行流程：
  /// 1. **防重入检查**：如果正在巡检则直接返回
  /// 2. **设置巡检标志**：isInspecting = true，禁用巡检按钮
  /// 3. **异步执行巡检**：调用 tagService.inspectNow()
  /// 4. **清除巡检标志**：isInspecting = false，重新启用巡检按钮
  ///
  /// 巡检内容：
  /// - 检查所有图片记录的文件是否存在
  /// - 尝试通过安全书签恢复访问权限
  /// - 移除无法访问的无效记录
  /// - 更新巡检统计摘要
  ///
  /// UI 反馈：
  /// - isInspecting 控制巡检按钮的禁用状态
  /// - 巡检完成后自动更新 inspectionDescription
  /// - TagService 会发布反馈事件，显示在 feedbackBanner
  ///
  /// 使用场景：
  /// - 用户手动触发巡检按钮
  /// - 定期检查数据库健康状态
  /// - 清理无效的图片记录
  private func runInspectionNow() {
    guard !isInspecting else { return }
    Task { @MainActor in
      isInspecting = true
      await tagService.inspectNow()
      isInspecting = false
    }
  }

  /// 标签列表视图
  ///
  /// 显示所有标签的可滚动列表，支持批量选择和单标签操作。
  ///
  /// 参数：
  /// - embedInContainer: 是否嵌入容器中
  ///   - true：无背景容器，直接嵌入父视图
  ///   - false：带有半透明背景和内边距
  ///
  /// 布局结构：
  /// - **ScrollView**：垂直滚动容器
  /// - **LazyVStack**：懒加载垂直栈，提高性能
  /// - **TagManagementRow**：每个标签的行视图
  ///   - 支持批量选择（checkbox）
  ///   - 显示标签颜色、名称、使用次数
  ///   - 提供重命名、删除、修改颜色操作
  /// - **Divider**：标签之间的分隔线（最后一个标签无分隔线）
  ///
  /// 视觉设计：
  /// - **高度**：根据标签数量动态计算（listHeight）
  /// - **背景**：根据 embedInContainer 参数决定是否显示背景
  /// - **滚动指示器**：自动显示滚动条
  ///
  /// 交互功能：
  /// - **批量模式**：开启时显示多选框，可以批量选择标签
  /// - **颜色编辑**：点击颜色圆点可以修改标签颜色
  /// - **重命名**：点击重命名按钮弹出重命名弹窗
  /// - **删除**：点击删除按钮弹出删除确认对话框
  ///
  /// 数据绑定：
  /// - **selectionBinding**：标签选中状态（批量模式）
  /// - **colorBinding**：标签颜色编辑草稿
  /// - **onRename**：设置 editingTag 触发重命名弹窗
  /// - **onDelete**：设置 deletingTag 触发删除确认
  ///
  /// 使用场景：
  /// - 浏览和管理所有标签
  /// - 批量选择标签进行批量操作
  /// - 单独编辑标签属性
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

  /// 计算列表高度
  ///
  /// 根据标签数量动态计算列表的显示高度。
  ///
  /// 计算规则：
  /// - **行高**：每个标签行 56pt
  /// - **总高度**：标签数量 × 56pt + 12pt（内边距）
  /// - **最小高度**：2 个标签行的高度（112pt）
  /// - **最大高度**：360pt（防止列表过长）
  ///
  /// 返回值：
  /// - 在 [最小高度, 最大高度] 区间内的实际高度
  /// - 确保列表不会太小或太大
  ///
  /// 使用场景：
  /// - tagListSection 计算滚动容器的固定高度
  /// - 标签数量少时显示完整列表，数量多时显示滚动列表
  ///
  /// - Parameter count: 标签数量
  /// - Returns: 列表高度（pt）
  private func listHeight(for count: Int) -> CGFloat {
    let rowHeight: CGFloat = 56
    let totalHeight = CGFloat(count) * rowHeight + 12
    let maxHeight: CGFloat = 360
    return min(max(totalHeight, rowHeight * 2), maxHeight)
  }

  /// 格式化标签使用次数
  ///
  /// 将标签的使用次数格式化为本地化字符串。
  ///
  /// 格式：
  /// - "N 张图片" 或其他本地化表达
  ///
  /// 使用场景：
  /// - TagManagementRow 显示标签使用次数
  /// - 帮助用户了解标签的使用频率
  ///
  /// - Parameter count: 使用次数
  /// - Returns: 格式化后的字符串
  private func tagUsageSummary(for count: Int) -> String {
    String(format: L10n.string("tag_usage_format"), count)
  }

  /// 智能筛选器摘要文本
  ///
  /// 根据智能筛选器的状态生成摘要文本。
  ///
  /// 显示逻辑：
  /// 1. **无智能筛选器**：显示"暂无智能筛选器"
  /// 2. **有激活的筛选器**：显示"当前: [筛选器名称]"
  /// 3. **有筛选器但未激活**：显示"共 N 个筛选器"
  ///
  /// 使用场景：
  /// - CollapsibleToolSection 的 summary 参数
  /// - 智能筛选器面板折叠时显示的摘要
  ///
  /// - Returns: 智能筛选器状态摘要字符串
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

  /// 批量工具摘要文本
  ///
  /// 根据批量模式状态生成摘要文本。
  ///
  /// 显示逻辑：
  /// - **批量模式开启**：显示"已选择 N 个标签"
  /// - **批量模式关闭**：显示"批量工具已禁用"
  ///
  /// 使用场景：
  /// - CollapsibleToolSection 的 summary 参数
  /// - 批量工具面板折叠时显示的摘要
  ///
  /// - Returns: 批量工具状态摘要字符串
  private var batchToolsSummary: String {
    if store.isBatchModeEnabled {
      return String(
        format: L10n.string("tag_settings_batch_selection_count"),
        store.selectedTagIDs.count
      )
    }
    return L10n.string("tag_settings_batch_disabled_summary")
  }

  /// 打开智能筛选器重命名弹窗
  ///
  /// 预填充原名称并显示重命名弹窗。
  ///
  /// 执行流程：
  /// 1. **预填原名称**：设置 smartFilterRenameText 为筛选器的当前名称
  /// 2. **显示弹窗**：设置 renamingSmartFilter 为要重命名的筛选器
  ///
  /// 使用场景：
  /// - 用户点击智能筛选器的重命名按钮
  /// - TagSmartFilterSection 的 onRename 回调
  ///
  /// - Parameter filter: 要重命名的智能筛选器
  private func startRenamingSmartFilter(_ filter: TagSmartFilter) {
    smartFilterRenameText = filter.name
    renamingSmartFilter = filter
  }

  /// 当前激活的智能筛选器 ID
  ///
  /// 查找与当前筛选条件完全匹配的智能筛选器。
  ///
  /// 匹配逻辑：
  /// - 比较 tagService.activeFilter 和每个智能筛选器的 filter 字段
  /// - 使用 == 运算符（TagFilter 实现了 Equatable）
  /// - 所有筛选维度（标签、颜色、关键词、模式）都必须完全匹配
  ///
  /// 返回值：
  /// - **匹配成功**：返回智能筛选器的 ID
  /// - **无匹配**：返回 nil（当前筛选条件不是智能筛选器）
  ///
  /// 使用场景：
  /// - 智能筛选器列表中高亮当前激活的筛选器
  /// - 判断当前是否在使用智能筛选器
  ///
  /// - Returns: 激活的智能筛选器 ID，如果没有匹配则返回 nil
  private var activeSmartFilterID: TagSmartFilter.ID? {
    tagService.smartFilters.first(where: { $0.filter == tagService.activeFilter })?.id
  }

  /// 当前激活的智能筛选器名称
  ///
  /// 获取当前激活的智能筛选器的显示名称。
  ///
  /// 查找流程：
  /// 1. 获取当前激活的智能筛选器 ID（activeSmartFilterID）
  /// 2. 在 smartFilters 列表中查找对应 ID 的筛选器
  /// 3. 返回筛选器的名称
  ///
  /// 返回值：
  /// - **有激活的智能筛选器**：返回筛选器名称
  /// - **无激活的智能筛选器**：返回 nil
  ///
  /// 使用场景：
  /// - smartFilterSummary 显示当前激活的筛选器名称
  ///
  /// - Returns: 激活的智能筛选器名称，如果没有则返回 nil
  private var activeSmartFilterName: String? {
    guard let activeSmartFilterID else { return nil }
    return tagService.smartFilters.first(where: { $0.id == activeSmartFilterID })?.name
  }

  /// 标签 ID 到名称的映射字典
  ///
  /// 创建标签 ID 到名称的快速查找表。
  ///
  /// 数据来源：
  /// - tagService.allTags（全局所有标签）
  ///
  /// 生成方式：
  /// - 使用 Dictionary(uniqueKeysWithValues:) 从标签数组构造字典
  /// - key：标签 ID（Int64）
  /// - value：标签名称（String）
  ///
  /// 使用场景：
  /// - TagSmartFilterSection 显示智能筛选器的标签名称
  /// - 根据 ID 快速查找标签名称（O(1) 查找）
  ///
  /// - Returns: 标签 ID 到名称的字典映射
  /// 方便在列表和批量操作中根据 ID 查找名称
  private var tagNameLookup: [Int64: String] {
    Dictionary(uniqueKeysWithValues: tagService.allTags.map { ($0.id, $0.name) })
  }
}

/// 标签重命名弹窗
///
/// 用于重命名单个标签的弹出式对话框。
///
/// 功能特点：
/// - **预填原名称**：初始化时填充标签的当前名称
/// - **实时验证**：空白名称时禁用保存按钮
/// - **回车提交**：输入框支持回车键快速提交
///
/// 布局结构：
/// - **标题**：显示"重命名标签"
/// - **输入框**：文本输入，预填原名称
/// - **按钮行**：
///   - 取消按钮：关闭弹窗不保存
///   - 保存按钮：提交新名称并关闭
///
/// 验证规则：
/// - 去除首尾空白后非空才允许保存
/// - 保存按钮在名称无效时禁用
///
/// 交互流程：
/// 1. 弹窗打开，输入框显示原名称
/// 2. 用户编辑名称
/// 3. 点击保存或按回车键提交
/// 4. 调用 onSave 回调，传递新名称
/// 5. 关闭弹窗
///
/// 使用场景：
/// - 用户在标签管理页面点击重命名按钮
/// - 修正标签拼写错误
/// - 标签规范化
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

/// 批量添加标签弹窗
///
/// 用于批量创建多个标签的弹出式对话框。
///
/// 功能特点：
/// - **多分隔符支持**：支持逗号、分号、换行符分隔标签名称
/// - **多行输入**：使用 TextEditor 支持大量标签输入
/// - **实时验证**：空白输入时禁用保存按钮
///
/// 布局结构：
/// - **标题**：显示"批量添加标签"
/// - **提示文本**：说明分隔符规则
/// - **文本编辑器**：多行文本输入，最小高度 120pt
/// - **按钮行**：
///   - 取消按钮：关闭弹窗不保存
///   - 保存按钮：提交标签列表并关闭
///
/// 输入格式：
/// - 支持的分隔符：逗号（,）、分号（;）、换行符（\n）
/// - 示例：\"工作,重要;个人\n项目\"
///
/// 处理流程：
/// 1. 用户输入多个标签名称
/// 2. 点击保存按钮
/// 3. 解析输入文本，按分隔符分割
/// 4. 去除每个标签名称的空白字符
/// 5. 调用 onSubmit 回调，传递标签名称数组
/// 6. 清空输入框
/// 7. 关闭弹窗
///
/// 使用场景：
/// - 用户需要一次性创建多个标签
/// - 导入标签列表
/// - 预设常用标签
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

/// 标签合并弹窗
///
/// 用于将多个标签合并为一个目标标签的弹出式对话框。
///
/// 功能特点：
/// - **显示选中数量**：标题中显示要合并的标签数量
/// - **提示信息**：说明合并操作的影响
/// - **实时验证**：空白目标名称时禁用保存按钮
/// - **回车提交**：输入框支持回车键快速提交
///
/// 布局结构：
/// - **标题**：显示"合并 N 个标签"
/// - **提示文本**：说明合并规则
/// - **输入框**：输入目标标签名称
/// - **按钮行**：
///   - 取消按钮：关闭弹窗不保存
///   - 保存按钮：执行合并并关闭
///
/// 合并策略：
/// - 源标签的所有图片关联转移到目标标签
/// - 目标标签不存在时自动创建
/// - 源标签被删除
/// - 如果图片同时有源标签和目标标签，保留目标标签的关联
///
/// 交互流程：
/// 1. 弹窗打开，显示选中的标签数量
/// 2. 用户输入目标标签名称
/// 3. 点击保存或按回车键提交
/// 4. 调用 onSubmit 回调，传递目标名称
/// 5. 关闭弹窗
///
/// 使用场景：
/// - 清理重复标签（如"工作"和"Work"）
/// - 标签规范化（统一术语）
/// - 合并相似标签
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

/// 操作历史记录弹窗
///
/// 显示标签操作的历史反馈记录列表。
///
/// 功能特点：
/// - **历史记录列表**：显示最近的操作反馈
/// - **时间戳**：每条记录显示本地化的时间戳
/// - **状态图标**：成功/失败图标和颜色区分
/// - **导航栏**：标准导航栏，包含关闭按钮
///
/// 布局结构：
/// - **NavigationStack**：提供导航栏
/// - **List**：显示所有反馈记录
///   - 每条记录：图标 + 消息 + 时间戳
/// - **导航标题**：显示"操作历史"
/// - **工具栏**：关闭按钮
///
/// 记录格式：
/// - **成功**：绿色勾选图标 + 成功消息
/// - **失败**：橙色警告图标 + 错误消息
/// - **时间戳**：本地化的短格式时间（如"5分钟前"）
///
/// 数据来源：
/// - feedbacks 参数：TagService.feedbackHistory
/// - 最多显示 20 条最近的记录
///
/// 交互功能：
/// - 点击关闭按钮：调用 dismiss 回调关闭弹窗
/// - 滚动查看所有历史记录
///
/// 使用场景：
/// - 用户查看操作历史
/// - 调试和故障排查
/// - 确认操作是否成功执行
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

/// 设置页面动画配置
///
/// 统一管理设置页面中使用的动画效果。
///
/// 动画效果：
/// - **collapse**：折叠/展开动画
///   - 响应时间：0.24 秒
///   - 阻尼系数：0.92（轻微回弹）
///   - 混合持续时间：0.08 秒
///   - 效果：平滑的弹簧动画，适合折叠面板
///
/// 使用场景：
/// - CollapsibleToolSection 的折叠/展开
/// - 批量模式切换时的面板动画
/// - 其他需要平滑过渡的 UI 状态变化
enum SettingsAnimations {
  static let collapse = Animation.spring(
    response: 0.24,
    dampingFraction: 0.92,
    blendDuration: 0.08
  )
}

/// 可折叠工具区域组件
///
/// 通用的可折叠面板组件，用于显示可展开/折叠的工具区域。
///
/// 泛型参数：
/// - **Content**：面板内容视图类型
/// - **Trailing**：标题行尾部视图类型（默认 EmptyView）
///
/// 功能特点：
/// - **折叠/展开**：点击标题行切换展开状态
/// - **摘要文本**：折叠时显示内容摘要
/// - **自定义尾部**：标题行可以添加自定义控件（如 Toggle）
/// - **两种外观**：grouped（独立卡片）或 embedded（嵌入式）
/// - **动画过渡**：使用自定义动画平滑展开/折叠
///
/// 外观样式：
/// - **grouped**：
///   - 使用 GroupBox 容器
///   - 带有背景和边框
///   - 12pt 内边距
///   - 适合独立显示的面板
/// - **embedded**：
///   - 无容器背景
///   - 顶部 12pt 内边距，其他方向无内边距
///   - 适合嵌入到其他容器中
///
/// 布局结构：
/// 1. **标题行**（header）：
///    - 折叠/展开按钮（图标 + 标题 + 摘要 + 箭头）
///    - 尾部自定义视图（如 Toggle、按钮等）
/// 2. **内容区域**（contentWrapper）：
///    - 展开时显示内容（透明度 1）
///    - 折叠时隐藏内容（透明度 0，高度 0）
///    - 使用 clipped() 裁剪溢出内容
///
/// 交互功能：
/// - 点击标题行切换展开/折叠状态
/// - 展开/折叠时执行动画过渡
/// - 尾部视图独立交互，不触发折叠切换
///
/// 使用场景：
/// - 智能筛选器面板（grouped 样式）
/// - 批量工具面板（embedded 样式，带 Toggle）
/// - 其他需要折叠的工具区域
///
/// 示例：
/// ```swift
/// CollapsibleToolSection(
///   title: "工具",
///   summary: "已选择 5 个",
///   iconName: "square.stack.3d.up",
///   isExpanded: $isExpanded,
///   appearance: .embedded,
///   trailing: { Toggle("开启", isOn: $enabled) }
/// ) {
///   // 工具内容
/// }
/// ```
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

/// TagSettingsView 的私有扩展
///
/// 包含视图的计算属性和辅助方法。
private extension TagSettingsView {
  /// 搜索筛选后的标签列表
  ///
  /// 根据用户输入的搜索关键词筛选标签。
  ///
  /// 数据来源：
  /// - **base**：tagService.allTagsSortedByName（按名称排序的全局标签）
  /// - **keyword**：store.debouncedSearchText（防抖处理后的搜索文本）
  ///
  /// 筛选逻辑：
  /// - 关键词为空：返回所有标签（无筛选）
  /// - 关键词非空：返回名称包含关键词的标签
  /// - 不区分大小写匹配
  ///
  /// 性能优化：
  /// - store 内部使用防抖机制，避免高频搜索
  /// - 只在关键词稳定后执行筛选
  ///
  /// 使用场景：
  /// - 搜索框输入变化时更新列表
  /// - tagContentSection 显示筛选后的标签
  ///
  /// - Returns: 筛选后的标签数组
  var filteredTags: [TagRecord] {
    let base = tagService.allTagsSortedByName
    let keyword = store.debouncedSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !keyword.isEmpty else { return base }
    return base.filter { tag in
      tag.name.localizedCaseInsensitiveContains(keyword)
    }
  }

  /// 标签总数
  ///
  /// 全局所有标签的数量，包括已使用和未使用的标签。
  ///
  /// 数据来源：
  /// - tagService.allTags（全局标签列表）
  ///
  /// 使用场景：
  /// - TagStatsCard 显示标签统计
  /// - 统计面板显示总数
  ///
  /// - Returns: 标签总数
  var totalTags: Int {
    tagService.allTags.count
  }

  /// 已使用的标签数量
  ///
  /// 至少有一张图片关联的标签数量。
  ///
  /// 计算逻辑：
  /// - 筛选 usageCount > 0 的标签
  /// - 统计数量
  ///
  /// 数据来源：
  /// - tagService.allTags（全局标签列表）
  /// - TagRecord.usageCount（标签的使用次数）
  ///
  /// 使用场景：
  /// - TagStatsCard 显示已使用标签数量
  /// - 帮助用户了解标签的实际使用情况
  ///
  /// - Returns: 已使用的标签数量
  var usedTags: Int {
    tagService.allTags.filter { $0.usageCount > 0 }.count
  }

  /// 未使用的标签数量
  ///
  /// 没有任何图片关联的孤立标签数量。
  ///
  /// 计算逻辑：
  /// - 总标签数 - 已使用标签数
  /// - 使用 max(0, ...) 确保结果非负
  ///
  /// 数据来源：
  /// - totalTags（标签总数）
  /// - usedTags（已使用标签数量）
  ///
  /// 使用场景：
  /// - TagStatsCard 显示未使用标签数量
  /// - 提示用户可以清理的标签数量
  /// - 清理未使用标签功能的依据
  ///
  /// - Returns: 未使用的标签数量
  var unusedTags: Int {
    max(0, totalTags - usedTags)
  }
}
