//
//  TagFilterPanel.swift
//
//  标签筛选面板
//  在侧边栏显示的多维度筛选界面，支持关键词、颜色、标签、智能筛选器的组合筛选。
//
//  Created by Eric Cai on 2025/11/08.
//

import SwiftUI

/// 标签筛选面板
///
/// 显示在应用侧边栏的综合筛选界面，提供多维度的图片筛选功能。
///
/// 核心功能：
/// 1. **关键词筛选**：搜索文件名或目录名
/// 2. **颜色筛选**：按标签颜色多选筛选（支持搜索）
/// 3. **标签筛选**：按标签名称多选筛选（支持搜索）
/// 4. **智能筛选器**：快速应用保存的筛选条件组合
/// 5. **筛选模式**：any（任一）/all（全部）/exclude（排除）三种模式
///
/// 设计特点：
/// - **实时响应**：筛选条件变化立即更新图片列表
/// - **多维度组合**：支持关键词、颜色、标签的自由组合
/// - **智能推荐**：显示当前作用域内可用的标签和颜色
/// - **搜索支持**：颜色和标签都支持快速搜索定位
/// - **持久化**：可以将常用筛选条件保存为智能筛选器
///
/// 交互流程：
/// 1. 用户在各个筛选维度选择条件
/// 2. 条件实时写入 TagService.activeFilter
/// 3. ContentView 监听 activeFilter 变化并刷新图片列表
/// 4. 用户可以保存当前筛选条件为智能筛选器
///
/// 数据来源：
/// - **scopedTags**：当前显示图片集合中使用的标签（作用域标签）
/// - **allTags**：全局所有标签（用于提取颜色）
/// - **smartFilters**：用户保存的智能筛选器
/// - **activeFilter**：当前激活的筛选条件
///
/// 使用场景：
/// - 用户浏览图片时需要按条件筛选
/// - 管理大量图片时快速定位特定图片
/// - 批量操作前筛选目标图片
struct TagFilterPanel: View {
  /// 标签服务，提供筛选条件和标签数据
  @EnvironmentObject var tagService: TagService

  /// 当前语言环境，用于刷新菜单显示
  @Environment(\.locale) private var locale

  // MARK: - 批量操作回调

  /// 当前筛选结果的图片数量
  let visibleImageCount: Int

  /// 批量删除回调
  /// 当用户点击"删除 N 张图片"按钮时调用
  let onRequestBatchDeletion: () -> Void

  /// 是否正在筛选图片
  /// 筛选期间隐藏批量删除按钮，避免数字闪动
  let isFilteringImages: Bool

  // MARK: - 视图状态

  /// 智能筛选器命名草稿
  /// 用于在命名弹窗中编辑新的智能筛选器名称
  @State private var smartFilterDraftName: String = ""

  /// 智能筛选器命名弹窗显示状态
  @State private var showingSmartFilterSheet = false

  /// 颜色搜索文本
  /// 用于在颜色列表中快速搜索颜色值
  @State private var colorSearchText: String = ""

  /// 标签搜索文本
  /// 用于在标签列表中快速搜索标签名称
  @State private var tagSearchText: String = ""

  /// 关键词输入框的焦点状态
  /// 提交后可以重新聚焦，方便连续输入
  @FocusState private var keywordFocused: Bool

  /// 主视图布局
  ///
  /// 垂直排列的筛选面板，包含多个筛选维度。
  ///
  /// 布局结构（从上到下）：
  /// 1. **headerRow**：顶部工具栏
  ///    - 筛选模式切换菜单（any/all/exclude）
  ///    - 保存智能筛选器按钮
  /// 2. **keywordSection**：关键词搜索输入框
  /// 3. **colorSection**：颜色筛选网格（可选，有颜色时显示）
  /// 4. **tagSelectionSection**：标签多选列表
  /// 5. **smartFilterSection**：智能筛选器横向列表（可选，有智能筛选器时显示）
  /// 6. **footerRow**：底部清除按钮
  ///
  /// 视觉设计：
  /// - **背景**：半透明灰色圆角矩形
  /// - **分隔线**：各区域之间用 Divider 分隔
  /// - **内边距**：统一 12pt 内边距
  /// - **圆角**：12pt 连续曲线圆角
  ///
  /// 弹窗管理：
  /// - **命名弹窗**：showingSmartFilterSheet 控制智能筛选器命名面板显示
  ///
  /// 动态显示：
  /// - 颜色区域：只在有可用颜色时显示
  /// - 智能筛选器区域：只在有保存的智能筛选器时显示
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

  /// 顶部工具栏
  ///
  /// 布局：
  /// - **左侧**：筛选模式下拉菜单（modeMenu）
  /// - **右侧**：保存智能筛选器按钮
  ///
  /// 按钮功能：
  /// - **模式菜单**：切换 any/all/exclude 筛选模式
  /// - **保存按钮**：将当前筛选条件保存为智能筛选器
  ///
  /// 按钮状态：
  /// - 保存按钮在筛选条件为空时禁用（!activeFilter.isActive）
  ///
  /// 使用场景：
  /// - 用户需要切换筛选逻辑（任一匹配 vs 全部匹配）
  /// - 用户配置好筛选条件后保存为智能筛选器
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

  /// 关键词搜索区域
  ///
  /// 功能：
  /// - 搜索文件名或目录路径中包含的关键词
  /// - 不区分大小写
  /// - 包含匹配（不是精确匹配）
  ///
  /// 交互：
  /// - 实时搜索：每次输入都会更新筛选条件
  /// - 回车提交：手动 trim 确保条件准确
  /// - 焦点管理：支持键盘操作
  ///
  /// 数据绑定：
  /// - 使用 keywordBinding 自动同步到 TagService.activeFilter
  ///
  /// 使用场景：
  /// - 用户记得文件名的一部分
  /// - 按目录路径筛选图片
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

  /// 颜色筛选区域
  ///
  /// 功能：
  /// - 按标签颜色多选筛选图片
  /// - 支持搜索颜色值（#RRGGBB 格式）
  /// - 网格布局显示所有可用颜色
  ///
  /// 布局结构：
  /// 1. **标题行**：
  ///    - "颜色" 标题
  ///    - 选中数量统计
  ///    - "清除颜色" 按钮
  /// 2. **搜索框**：快速搜索颜色值
  /// 3. **颜色网格**：
  ///    - 少于等于 6 个颜色：内联显示
  ///    - 超过 6 个颜色：可滚动显示（最大高度 110pt）
  /// 4. **空状态**：搜索无结果时显示提示
  ///
  /// 数据来源：
  /// - **availableColors**：从 scopedTags 和 allTags 中提取的所有颜色
  /// - **filteredColors**：根据 colorSearchText 筛选后的颜色
  ///
  /// 交互：
  /// - 点击颜色按钮：切换选中/取消选中
  /// - 清除按钮：清空所有颜色筛选条件
  /// - 搜索框：实时筛选颜色列表
  ///
  /// 视觉设计：
  /// - 选中的颜色有主题色背景和边框
  /// - 未选中的颜色有灰色边框
  /// - 清除按钮在没有选中颜色时半透明禁用
  ///
  /// 使用场景：
  /// - 用户按颜色分类管理图片
  /// - 快速定位特定颜色标记的图片
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
  ///
  /// 功能：
  /// - 快速应用保存的筛选条件组合
  /// - 横向滚动显示所有智能筛选器
  /// - 高亮当前激活的智能筛选器
  ///
  /// 布局：
  /// - **标题**："智能筛选" 文本标题
  /// - **横向列表**：可滚动的智能筛选器按钮列表
  ///
  /// 交互：
  /// - 点击筛选器按钮：应用该筛选器的条件
  /// - 当前激活的筛选器：白色文字 + 主题色背景
  /// - 其他筛选器：主色文字 + 半透明主题色背景
  ///
  /// 数据来源：
  /// - **smartFilters**：用户保存的智能筛选器列表
  ///
  /// 视觉设计：
  /// - 胶囊形状按钮
  /// - 激活状态：实色背景，白色文字
  /// - 非激活状态：半透明背景，主色文字
  ///
  /// 使用场景：
  /// - 用户频繁使用相同的筛选条件组合
  /// - 快速切换不同的筛选场景
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

  /// 区域分隔线
  ///
  /// 用于分隔不同的筛选区域，增加视觉层次感。
  ///
  /// 样式：
  /// - 标准 Divider 分隔线
  /// - 上下各 10pt 内边距
  private var sectionDivider: some View {
    Divider()
      .padding(.vertical, 10)
  }

  /// 空状态视图
  ///
  /// 当作用域内没有任何标签时显示的提示信息。
  ///
  /// 使用场景：
  /// - 用户刚开始使用标签功能
  /// - 当前目录没有图片
  /// - 所有图片都没有标签
  ///
  /// 提示内容：
  /// - 说明如何添加标签
  /// - 引导用户开始使用标签功能
  private var emptyStateView: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(L10n.string("tag_filter_empty_hint"))
        .font(.footnote)
        .foregroundColor(.secondary)
    }
  }

  /// 底部清除按钮区域
  ///
  /// 功能：
  /// - 批量删除筛选结果的图片
  /// - 清除所有筛选条件，恢复显示全部图片
  ///
  /// 布局：
  /// - 左侧：批量删除按钮（新增）
  /// - 右侧：清除筛选按钮
  ///
  /// 按钮状态：
  /// - 有筛选条件且有可见图片时：批量删除按钮可用
  /// - 筛选期间：隐藏批量删除按钮，避免数字闪动
  /// - 有筛选条件时：清除筛选按钮可用
  ///
  /// 交互：
  /// - 批量删除按钮：调用 onRequestBatchDeletion 回调
  /// - 清除筛选按钮：调用 tagService.clearFilter() 清除所有条件
  ///
  /// 使用场景：
  /// - 用户筛选后想批量删除符合条件的图片
  /// - 用户筛选后想查看全部图片
  /// - 重置筛选条件重新开始
  private var footerRow: some View {
    let canClearAll = tagService.activeFilter.isActive
    let canBatchDelete = canClearAll && visibleImageCount > 0 && !isFilteringImages
    return HStack(spacing: 12) {
      // 批量删除按钮（新增）
      // 只在筛选完成且有结果时显示，避免闪动
      if canBatchDelete {
        Button {
          onRequestBatchDeletion()
        } label: {
          Label(
            String(format: L10n.string("batch_delete_button"), visibleImageCount),
            systemImage: "trash.fill"
          )
        }
        .buttonStyle(.borderless)
        .foregroundColor(.red)
        .help(L10n.string("batch_delete_button_tooltip"))
      }

      Spacer()

      // 清除筛选按钮（现有）
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

  /// 筛选模式菜单
  ///
  /// 功能：
  /// - 切换标签筛选的逻辑模式
  ///
  /// 筛选模式：
  /// 1. **any（任一）**：图片有任何一个选中的标签即匹配
  /// 2. **all（全部）**：图片必须有所有选中的标签才匹配
  /// 3. **exclude（排除）**：图片不能有任何选中的标签
  ///
  /// 布局：
  /// - 下拉菜单，显示所有可选模式
  /// - 当前模式显示勾选标记
  ///
  /// 数据绑定：
  /// - 读取和修改 tagService.activeFilter.mode
  ///
  /// 语言切换：
  /// - 使用 .id("mode-menu-\(locale.identifier)") 确保切换语言时重新渲染
  ///
  /// 使用场景：
  /// - 用户需要精确控制标签筛选逻辑
  /// - 查找同时有多个标签的图片（all 模式）
  /// - 排除某些标签的图片（exclude 模式）
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

  /// 标签选择区域
  ///
  /// 功能：
  /// - 按标签名称多选筛选图片
  /// - 支持搜索标签名称和使用次数
  /// - 显示每个标签在作用域内的使用次数
  ///
  /// 布局结构：
  /// 1. **空状态**：作用域内没有标签时显示提示
  /// 2. **标题行**：
  ///    - "标签" 标题
  ///    - 选中数量统计
  ///    - "清除标签" 按钮
  /// 3. **搜索框**：快速搜索标签名称
  /// 4. **标签列表**：可滚动的标签多选列表
  ///
  /// 数据来源：
  /// - **scopedTags**：当前作用域内的标签及其使用次数
  /// - **filteredTags**：根据 tagSearchText 筛选后的标签
  ///
  /// 交互：
  /// - 点击标签行：切换选中/取消选中
  /// - 清除按钮：清空所有标签筛选条件
  /// - 搜索框：实时筛选标签列表
  ///
  /// 视觉设计：
  /// - 选中的标签有主题色背景和勾选图标
  /// - 未选中的标签有空心圆圈图标
  /// - 显示标签颜色圆点和使用次数
  /// - 清除按钮在没有选中标签时半透明禁用
  ///
  /// 使用场景：
  /// - 用户按标签分类管理图片
  /// - 查找有特定标签的图片
  /// - 组合多个标签筛选
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
  ///
  /// 功能：
  /// - 垂直滚动显示所有标签
  /// - 懒加载标签行，提高性能
  /// - 空状态提示
  ///
  /// 布局：
  /// - **LazyVStack**：懒加载容器，只渲染可见行
  /// - **ScrollView**：支持垂直滚动
  /// - **固定高度范围**：最小 120pt，最大 300pt
  ///
  /// 空状态：
  /// - 搜索无结果时显示提示文本
  ///
  /// 性能优化：
  /// - 使用 LazyVStack 延迟加载
  /// - 每个标签行独立渲染，避免整体重绘
  ///
  /// 使用场景：
  /// - 标签数量较多时滚动查看
  /// - 搜索定位特定标签
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

  /// 标签选择统计
  ///
  /// 显示当前选中的标签数量。
  ///
  /// 格式：
  /// - 0 个选中："未选择"
  /// - N 个选中："已选择 N 个"
  ///
  /// 使用场景：
  /// - 显示在标签区域的标题行
  /// - 帮助用户了解当前的筛选状态
  private var selectionSummary: String {
    let count = tagService.activeFilter.tagIDs.count
    if count == 0 {
      return L10n.string("tag_filter_selection_summary_none")
    }
    return String(format: L10n.string("tag_filter_selection_summary_some"), count)
  }

  /// 颜色选择统计
  ///
  /// 显示当前选中的颜色数量。
  ///
  /// 格式：
  /// - 0 个选中："未选择"
  /// - N 个选中："已选择 N 个"
  ///
  /// 使用场景：
  /// - 显示在颜色区域的标题行
  /// - 帮助用户了解当前的颜色筛选状态
  private var colorSelectionSummary: String {
    let count = tagService.activeFilter.colorHexes.count
    if count == 0 {
      return L10n.string("tag_filter_color_summary_none")
    }
    return String(format: L10n.string("tag_filter_color_summary_some"), count)
  }

  /// 格式化标签使用次数
  ///
  /// 将标签的使用次数格式化为本地化字符串。
  ///
  /// 格式：
  /// - "N 张图片" 或其他本地化表达
  ///
  /// 使用场景：
  /// - 显示在标签行中
  /// - 帮助用户了解标签的使用频率
  ///
  /// - Parameter count: 使用次数
  /// - Returns: 格式化后的字符串
  private func tagUsageSummary(for count: Int) -> String {
    String(format: L10n.string("tag_usage_format"), count)
  }

  /// 关键词输入框的自定义 Binding
  ///
  /// 功能：
  /// - 读取和写入实时同步到 TagService.activeFilter
  /// - 每次输入都会触发筛选
  ///
  /// 实现：
  /// - **get**：从 activeFilter 读取当前关键词
  /// - **set**：调用 tagService.updateKeywordFilter 更新关键词
  ///
  /// 使用场景：
  /// - 绑定到关键词输入框
  /// - 确保关键词变化实时更新筛选结果
  private var keywordBinding: Binding<String> {
    Binding(
      get: { tagService.activeFilter.keyword },
      set: { tagService.updateKeywordFilter($0) }
    )
  }

  /// 提交关键词输入
  ///
  /// 功能：
  /// - 手动结束编辑时清理关键词
  /// - 去除首尾空白字符，确保筛选条件准确
  ///
  /// 执行时机：
  /// - 用户按回车键提交（.onSubmit）
  /// - 输入框失去焦点时（可选）
  ///
  /// 实现：
  /// - 读取当前关键词
  /// - trim 首尾空白
  /// - 更新到 TagService
  ///
  /// 使用场景：
  /// - 用户粘贴带空白的文本后提交
  /// - 确保搜索条件精确
  private func commitKeyword() {
    tagService.updateKeywordFilter(
      tagService.activeFilter.keyword.trimmingCharacters(in: .whitespacesAndNewlines)
    )
  }

  /// 从作用域和全局标签中提取所有可用颜色
  ///
  /// 功能：
  /// - 合并作用域标签和全局标签的颜色
  /// - 去重并排序
  /// - 归一化颜色值（#RRGGBB 格式）
  ///
  /// 数据来源：
  /// - **scopedTags**：当前作用域内标签的颜色
  /// - **allTags**：全局所有标签的颜色
  ///
  /// 处理逻辑：
  /// 1. 提取作用域标签的颜色（非 nil）
  /// 2. 提取全局标签的颜色（非 nil）
  /// 3. 归一化颜色值（统一格式）
  /// 4. 去重（使用 Set）
  /// 5. 排序（字母序）
  ///
  /// 为什么包含全局标签：
  /// - 用户可能想筛选不在当前作用域的颜色
  /// - 提供更完整的颜色选项
  ///
  /// - Returns: 排序后的颜色数组
  private var availableColors: [String] {
    let scoped = tagService.scopedTags.compactMap { $0.colorHex.normalizedHexColor() }
    let global = tagService.allTags.compactMap { $0.colorHex.normalizedHexColor() }
    return Array(Set(scoped + global)).sorted()
  }

  /// 根据搜索文本筛选颜色
  ///
  /// 功能：
  /// - 搜索颜色的 HEX 值
  /// - 不区分大小写
  /// - 包含匹配
  ///
  /// 搜索逻辑：
  /// - 搜索文本为空：返回所有颜色
  /// - 搜索文本非空：返回包含搜索文本的颜色
  ///
  /// 使用场景：
  /// - 用户在颜色列表中快速定位颜色
  /// - 颜色数量较多时搜索定位
  ///
  /// - Returns: 筛选后的颜色数组
  private var filteredColors: [String] {
    let query = colorSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !query.isEmpty else { return availableColors }
    return availableColors.filter { $0.localizedCaseInsensitiveContains(query) }
  }

  /// 根据搜索文本筛选标签
  ///
  /// 功能：
  /// - 搜索标签名称或使用次数
  /// - 不区分大小写
  /// - 包含匹配
  ///
  /// 搜索逻辑：
  /// - 搜索文本为空：返回所有作用域标签
  /// - 搜索文本非空：返回匹配的标签
  ///
  /// 搜索范围：
  /// - **标签名称**：主要搜索字段
  /// - **使用次数**：次要搜索字段（如搜索 "5" 可以找到使用 5 次的标签）
  ///
  /// 使用场景：
  /// - 用户在标签列表中快速定位标签
  /// - 标签数量较多时搜索定位
  /// - 按使用次数筛选标签
  ///
  /// - Returns: 筛选后的标签数组
  private var filteredTags: [ScopedTagSummary] {
    let query = tagSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !query.isEmpty else { return tagService.scopedTags }
    return tagService.scopedTags.filter { tag in
      tag.name.localizedCaseInsensitiveContains(query) ||
        "\(tag.usageCount)".localizedStandardContains(query)
    }
  }

  /// 获取当前激活的智能筛选器 ID
  ///
  /// 功能：
  /// - 检测当前筛选条件是否与某个智能筛选器完全一致
  /// - 用于高亮当前使用的智能筛选器
  ///
  /// 匹配逻辑：
  /// - 比较 activeFilter 和每个智能筛选器的 filter 字段
  /// - 使用 == 运算符（TagFilter 实现了 Equatable）
  ///
  /// 返回值：
  /// - 匹配的智能筛选器 ID
  /// - nil 表示当前筛选条件不是智能筛选器
  ///
  /// 使用场景：
  /// - 在智能筛选器列表中高亮当前激活的筛选器
  /// - 视觉反馈用户当前使用的筛选组合
  private var activeSmartFilterID: TagSmartFilter.ID? {
    tagService.smartFilters.first(where: { $0.filter == tagService.activeFilter })?.id
  }

  /// 颜色网格的列配置
  ///
  /// 功能：
  /// - 定义颜色网格的布局
  /// - 3 列自适应宽度
  ///
  /// 配置：
  /// - **列数**：3 列
  /// - **宽度**：flexible，最小 80pt
  /// - **间距**：8pt 列间距
  /// - **对齐**：左对齐
  ///
  /// 使用场景：
  /// - LazyVGrid 的 columns 参数
  /// - 颜色网格的布局控制
  private var colorGridColumns: [GridItem] {
    Array(
      repeating: GridItem(.flexible(minimum: 80), spacing: 8, alignment: .leading),
      count: 3
    )
  }

  /// 颜色内联显示的数量限制
  ///
  /// 超过此数量的颜色会使用滚动视图显示。
  private let colorInlineLimit = 6

  /// 颜色滚动区域的最大高度（pt）
  ///
  /// 限制颜色列表的高度，避免占用过多空间。
  private let colorScrollMaxHeight: CGFloat = 110

  /// 禁用按钮的不透明度
  ///
  /// 用于视觉上区分禁用和启用状态的按钮。
  private let disabledButtonOpacity: Double = 0.55

  /// 单个颜色筛选按钮
  ///
  /// 功能：
  /// - 显示颜色圆点和 HEX 值
  /// - 支持选中/取消选中
  /// - 视觉区分选中状态
  ///
  /// 布局：
  /// - 颜色圆点（TagColorIcon）
  /// - HEX 值文本
  /// - 胶囊形状容器
  ///
  /// 视觉状态：
  /// - **选中**：主题色半透明背景 + 主题色边框
  /// - **未选中**：透明背景 + 灰色边框
  ///
  /// 交互：
  /// - 点击按钮：调用 tagService.toggleColorFilter 切换选中状态
  ///
  /// 使用场景：
  /// - colorSection 中的颜色网格
  /// - 用户点击颜色进行筛选
  ///
  /// - Parameter hex: 颜色的 HEX 值（#RRGGBB 格式）
  /// - Returns: 颜色按钮视图
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

  /// 颜色网格内容
  ///
  /// 功能：
  /// - 将颜色列表布局为 3 列网格
  /// - 懒加载颜色按钮
  ///
  /// 布局：
  /// - **LazyVGrid**：懒加载网格，提高性能
  /// - **3 列**：使用 colorGridColumns 配置
  /// - **8pt 间距**：行列之间的间距
  ///
  /// 性能优化：
  /// - 使用 LazyVGrid 延迟加载
  /// - 只渲染可见的颜色按钮
  ///
  /// 使用场景：
  /// - colorSection 中显示颜色列表
  /// - 内联显示或滚动显示
  ///
  /// - Parameter colors: 要显示的颜色数组
  /// - Returns: 颜色网格视图
  @ViewBuilder
  private func colorGridContent(_ colors: [String]) -> some View {
    LazyVGrid(columns: colorGridColumns, spacing: 8) {
      ForEach(colors, id: \.self) { hex in
        colorChip(for: hex)
      }
    }
    .padding(.vertical, 2)
  }

  /// 标签行视图
  ///
  /// 功能：
  /// - 显示标签的详细信息
  /// - 支持选中/取消选中
  /// - 视觉区分选中状态
  ///
  /// 布局：
  /// - **颜色圆点**：标签的颜色标识
  /// - **标签名称**：标签文本
  /// - **使用次数**：作用域内的使用次数
  /// - **选中图标**：勾选或空心圆圈
  ///
  /// 视觉状态：
  /// - **选中**：主题色半透明背景 + 填充勾选图标
  /// - **未选中**：透明背景 + 空心圆圈图标
  ///
  /// 交互：
  /// - 点击整行：调用 tagService.toggleFilter 切换选中状态
  /// - 切换时保持当前的筛选模式（any/all/exclude）
  ///
  /// 使用场景：
  /// - tagList 中显示标签
  /// - 用户点击标签进行筛选
  ///
  /// - Parameter tag: 要显示的标签记录
  /// - Returns: 标签行视图
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

  /// 弹出智能筛选器命名面板
  ///
  /// 功能：
  /// - 清空命名草稿
  /// - 显示命名弹窗
  ///
  /// 执行流程：
  /// 1. 重置 smartFilterDraftName 为空字符串
  /// 2. 设置 showingSmartFilterSheet 为 true 显示弹窗
  ///
  /// 为什么重置草稿：
  /// - 避免上次输入的名称残留
  /// - 确保用户每次看到的是空白输入框
  ///
  /// 使用场景：
  /// - 用户点击"保存智能筛选器"按钮
  /// - headerRow 中的保存按钮触发
  private func presentSmartFilterSheet() {
    smartFilterDraftName = ""
    showingSmartFilterSheet = true
  }

  /// 智能筛选器按钮
  ///
  /// 功能：
  /// - 显示智能筛选器的名称
  /// - 高亮当前激活的筛选器
  ///
  /// 视觉状态：
  /// - **激活**：实色主题色背景 + 白色文字
  /// - **非激活**：半透明主题色背景 + 主色文字
  ///
  /// 布局：
  /// - 胶囊形状按钮
  /// - 水平内边距 12pt，垂直内边距 6pt
  /// - 主题色边框（激活时实色，非激活时半透明）
  ///
  /// 交互：
  /// - 点击按钮：应用该智能筛选器的条件
  ///
  /// 使用场景：
  /// - smartFilterSection 中显示筛选器列表
  /// - 用户快速切换筛选条件组合
  ///
  /// - Parameter filter: 智能筛选器记录
  /// - Returns: 筛选器按钮视图
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

  /// 将筛选模式枚举转换为本地化字符串
  ///
  /// 功能：
  /// - 将 TagFilterMode 枚举值转换为用户可读的文本
  /// - 支持本地化
  ///
  /// 模式对应：
  /// - **any**：任一匹配（有任何一个选中标签即匹配）
  /// - **all**：全部匹配（必须有所有选中标签才匹配）
  /// - **exclude**：排除（不能有任何选中标签）
  ///
  /// 使用场景：
  /// - modeMenu 中显示模式选项
  /// - 确保 UI 文本与语言设置一致
  ///
  /// - Parameter mode: 筛选模式枚举值
  /// - Returns: 本地化的模式名称字符串
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

/// 智能筛选器命名弹窗
///
/// 通用的命名弹窗组件，用于保存智能筛选器或其他需要命名的功能。
///
/// 核心功能：
/// 1. **命名输入**：文本框输入筛选器名称
/// 2. **验证**：检查名称是否为空
/// 3. **保存回调**：调用传入的 onSave 闭包保存数据
/// 4. **错误显示**：显示保存失败的错误信息
/// 5. **取消操作**：关闭弹窗不保存
///
/// 设计特点：
/// - **可配置**：标题、占位符、按钮文本都通过参数配置
/// - **错误反馈**：捕获并显示保存失败的错误
/// - **键盘支持**：回车键提交，自动清除错误
/// - **禁用逻辑**：空名称时禁用保存按钮
///
/// 参数说明：
/// - **name**：绑定的命名输入文本
/// - **titleKey**：弹窗标题的本地化 key
/// - **placeholderKey**：输入框占位符的本地化 key
/// - **actionKey**：保存按钮文本的本地化 key
/// - **onSave**：保存回调闭包，参数为用户输入的名称，可能抛出错误
///
/// 交互流程：
/// 1. 用户输入名称
/// 2. 点击保存按钮或按回车键
/// 3. 验证名称非空
/// 4. 调用 onSave 闭包
/// 5. 成功：关闭弹窗
/// 6. 失败：显示错误信息
///
/// 错误处理：
/// - onSave 抛出错误时捕获并显示
/// - 错误信息显示在输入框下方
/// - 用户修改名称时自动清除错误
///
/// 使用场景：
/// - 保存智能筛选器
/// - 创建新的标签分类
/// - 其他需要命名的功能
///
/// 示例：
/// ```swift
/// SmartFilterNameSheet(
///   name: $draftName,
///   titleKey: "save_filter_title",
///   placeholderKey: "filter_name_placeholder",
///   actionKey: "save_button"
/// ) { name in
///   try service.saveFilter(named: name)
/// }
/// ```
struct SmartFilterNameSheet: View {
  /// 环境变量：用于关闭弹窗
  @Environment(\.dismiss) private var dismiss

  /// 命名输入文本（双向绑定）
  ///
  /// 从父视图传入，用户输入会同步回父视图。
  @Binding var name: String

  /// 弹窗标题的本地化 key
  ///
  /// 用于显示弹窗顶部的标题文本。
  let titleKey: String

  /// 输入框占位符的本地化 key
  ///
  /// 用于显示输入框的提示文本。
  let placeholderKey: String

  /// 保存按钮文本的本地化 key
  ///
  /// 用于显示保存按钮的文本。
  let actionKey: String

  /// 保存回调闭包
  ///
  /// 参数：
  /// - name: 用户输入的名称（已 trim 空白）
  ///
  /// 返回：
  /// - 无返回值
  ///
  /// 异常：
  /// - 可能抛出错误（如名称重复、存储失败等）
  let onSave: (String) throws -> Void

  /// 错误信息文本
  ///
  /// 保存失败时显示的错误消息。
  /// nil 表示没有错误。
  @State private var errorMessage: String?

  /// 主视图布局
  ///
  /// 垂直排列的弹窗内容：
  /// 1. **标题**：显示弹窗标题
  /// 2. **输入框**：命名文本输入
  /// 3. **错误提示**（可选）：显示错误信息
  /// 4. **按钮行**：取消和保存按钮
  ///
  /// 交互：
  /// - 输入框支持回车提交（.onSubmit）
  /// - 输入内容变化时清除错误
  /// - 保存按钮在名称为空时禁用
  ///
  /// 视觉设计：
  /// - 24pt 内边距
  /// - 16pt 垂直间距
  /// - headline 字体标题
  /// - 错误文本粉色显示
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

  /// 执行保存操作
  ///
  /// 功能：
  /// - 验证名称非空
  /// - 调用 onSave 闭包
  /// - 处理成功/失败情况
  ///
  /// 执行流程：
  /// 1. **清理名称**：去除首尾空白字符
  /// 2. **验证非空**：空名称直接返回
  /// 3. **调用回调**：执行 onSave(trimmed)
  /// 4. **成功处理**：
  ///    - 清除错误信息
  ///    - 关闭弹窗
  /// 5. **失败处理**：
  ///    - 捕获错误
  ///    - 显示错误信息
  ///    - 保持弹窗打开
  ///
  /// 错误处理：
  /// - 使用 do-catch 捕获 onSave 抛出的异常
  /// - 将 error.localizedDescription 显示给用户
  ///
  /// 使用场景：
  /// - 用户点击保存按钮
  /// - 用户在输入框中按回车键
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
