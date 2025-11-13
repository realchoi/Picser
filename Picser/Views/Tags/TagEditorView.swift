//
//  TagEditorView.swift
//
//  标签编辑器视图
//  在图片详情区域底部显示，支持为单张或多张图片批量添加、移除标签。
//
//  Created by Eric Cai on 2025/11/08.
//

import SwiftUI

/// 标签编辑器视图
///
/// 显示在 DetailView 底部的标签管理界面，提供完整的标签操作功能。
///
/// 核心功能：
/// 1. **查看标签**：显示当前图片已有的所有标签
/// 2. **添加标签**：通过文本输入或标签库选择添加新标签
/// 3. **移除标签**：点击标签上的删除按钮移除
/// 4. **批量操作**：支持同时为多张图片添加相同的标签
/// 5. **推荐标签**：基于目录和作用域热度推荐常用标签
/// 6. **颜色管理**：点击标签颜色圆点可以修改标签颜色
///
/// 设计特点：
/// - **批量选择**：通过菜单选择要操作的图片集合
/// - **标签推荐**：智能推荐可能需要的标签，提高标记效率
/// - **多种输入**：支持逗号、分号、换行符分隔的批量输入
/// - **即时反馈**：标签添加/移除后立即更新 UI
/// - **颜色编辑**：弹出式颜色选择器，支持保存和清除颜色
///
/// 使用场景：
/// - 用户在浏览图片时需要添加标签
/// - 批量整理图片标签
/// - 使用推荐标签快速标记
///
/// 数据流：
/// - 通过 @EnvironmentObject 获取 TagService
/// - 使用 .task(id:) 监听依赖变化，自动刷新推荐标签
/// - 批量选择状态同步到 imageURL 和 imageURLs 的变化
struct TagEditorView: View {
  /// 当前主要显示的图片 URL
  let imageURL: URL

  /// 当前作用域内的所有图片 URL 列表
  /// 用于批量选择和操作
  let imageURLs: [URL]

  /// 标签服务，提供标签的增删改查功能
  @EnvironmentObject var tagService: TagService

  /// 用户在文本框中输入的标签文本
  /// 支持多个标签用逗号、分号或换行符分隔
  @State private var tagInput: String = ""

  /// 文本框的焦点状态
  /// 提交后自动重新聚焦，方便连续输入
  @FocusState private var inputFocused: Bool

  /// 批量操作选中的图片集合
  /// 空集合时默认只操作当前图片
  @State private var batchSelection: Set<URL> = []

  /// 正在编辑颜色的标签
  /// 非 nil 时显示颜色编辑弹窗
  @State private var colorEditorTag: TagRecord?

  /// 颜色编辑器的当前颜色
  /// 打开颜色编辑器时初始化为标签的当前颜色
  @State private var colorEditorColor: Color = .accentColor

  /// 推荐的标签列表
  /// 基于目录热度和作用域热度计算
  @State private var recommendedSuggestions: [TagRecord] = []

  /// 已应用在当前主图片上的标签列表
  ///
  /// 计算属性，从 TagService 读取当前图片的标签并按名称排序。
  ///
  /// 排序规则：
  /// - 不区分大小写的字母序排序
  /// - 确保标签显示顺序一致
  ///
  /// - Returns: 排序后的标签数组
  private var assignedTags: [TagRecord] {
    tagService
      .tags(for: imageURL)
      .sorted {
        $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
      }
  }

  /// 文本框输入是否有效
  ///
  /// 验证规则：去除空白字符后非空
  ///
  /// - Returns: true 表示可以提交输入
  private var isInputValid: Bool {
    !tagInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  /// 批量操作选中的图片数量
  ///
  /// 至少为 1（即使 batchSelection 为空，也会操作当前图片）
  ///
  /// - Returns: 选中的图片数量
  private var selectionCount: Int {
    max(batchSelection.count, 1)
  }

  /// 全局标签库中的所有标签
  ///
  /// 按名称字母序排序，用于标签库菜单显示。
  ///
  /// - Returns: 排序后的标签数组
  private var sortedLibraryTags: [TagRecord] {
    tagService.allTagsSortedByName
  }

  /// 推荐标签的依赖触发器
  ///
  /// 组合了影响推荐结果的所有因素：
  /// - **imagePath**：当前图片路径
  /// - **assignmentsVersion**：标签分配缓存的版本号
  /// - **scopedHash**：作用域标签的哈希值
  ///
  /// 当任何一个因素变化时，触发 .task(id:) 重新计算推荐标签。
  ///
  /// - Returns: 推荐触发器对象
  private var recommendationTrigger: RecommendationTrigger {
    RecommendationTrigger(
      imagePath: imageURL.path,
      assignmentsVersion: tagService.assignmentsVersion,
      scopedHash: tagService.scopedTags.hashValue
    )
  }

  /// 初始化标签编辑器
  ///
  /// 执行初始化任务：
  /// 1. **标准化 URL**：将主图片和图片列表标准化为绝对路径
  /// 2. **初始化选择**：默认选中主图片
  ///
  /// - Parameters:
  ///   - imageURL: 当前主要显示的图片 URL
  ///   - imageURLs: 当前作用域内的所有图片 URL 列表
  init(imageURL: URL, imageURLs: [URL]) {
    let normalizedPrimary = imageURL.standardizedFileURL
    self.imageURL = normalizedPrimary
    self.imageURLs = imageURLs.map { $0.standardizedFileURL }
    _batchSelection = State(initialValue: [normalizedPrimary])
  }

  /// 主视图布局
  ///
  /// 垂直排列的视图组件：
  /// 1. **header**：标题行和标签库按钮
  /// 2. **batchSelectionControls**：批量选择控制菜单
  /// 3. **tagList**：当前图片已有的标签列表
  /// 4. **recommendedSection**：推荐标签列表
  /// 5. **inputRow**：标签输入框和添加按钮
  ///
  /// 视觉设计：
  /// - **毛玻璃背景**：使用 .ultraThinMaterial 实现半透明效果
  /// - **圆角矩形**：cornerRadius 12，连续曲线样式
  /// - **边框**：浅色边框线，提升层次感
  /// - **动画**：标签数量变化时执行 0.2 秒缓动动画
  ///
  /// 状态同步：
  /// - **imageURL 变化**：重置批量选择为新图片
  /// - **imageURLs 变化**：过滤掉不在新列表中的选择项
  ///
  /// 弹窗管理：
  /// - **colorEditorTag**：非 nil 时显示颜色编辑 sheet
  ///
  /// 推荐刷新：
  /// - **recommendationTrigger**：依赖变化时重新计算推荐标签
  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      header
      batchSelectionControls
      tagList
      recommendedSection
      inputRow
    }
    .padding(12)
    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: 12, style: .continuous)
        .strokeBorder(Color.primary.opacity(0.05))
    )
    .animation(.easeInOut(duration: 0.2), value: assignedTags.count)
    .onChange(of: imageURL) { _, newURL in
      batchSelection = [newURL.standardizedFileURL]
    }
    .onChange(of: imageURLs) { _, urls in
      let available = Set(urls.map { $0.standardizedFileURL })
      batchSelection = batchSelection.intersection(available)
      if batchSelection.isEmpty {
        batchSelection = [imageURL]
      }
    }
    .sheet(item: $colorEditorTag) { tag in
      TagColorEditorSheet(
        tag: tag,
        initialColor: colorEditorColor,
        onSave: { color in
          Task { await tagService.updateColor(tagID: tag.id, hex: color.hexString()) }
        },
        onClear: {
          Task { await tagService.updateColor(tagID: tag.id, hex: nil) }
        }
      )
    }
    .task(id: recommendationTrigger) {
      recommendedSuggestions = await tagService.recommendedTags(for: imageURL)
    }
  }
}

/// 私有视图组件扩展
///
/// 将 TagEditorView 的视图拆分为多个独立的计算属性，提高代码可读性。
private extension TagEditorView {
  /// 标题行和标签库按钮
  ///
  /// 布局：
  /// - **左侧**：标签图标 + "标签编辑" 文本
  /// - **右侧**：标签库下拉菜单按钮
  ///
  /// 标签库菜单：
  /// - 显示全局所有标签（按名称排序）
  /// - 点击标签后为选中的图片添加该标签
  /// - 标签为空时显示提示文本
  /// - 标签库为空时禁用按钮
  ///
  /// 视觉设计：
  /// - 标题使用次要色调（secondary）
  /// - 标签项带有颜色圆点
  var header: some View {
    HStack {
      Label(L10n.string("tag_editor_title"), systemImage: "tag")
        .labelStyle(.titleAndIcon)
        .font(.callout)
        .foregroundColor(.secondary)

      Spacer()

      Menu {
        if sortedLibraryTags.isEmpty {
          Text(L10n.string("tag_editor_no_tags"))
        } else {
          ForEach(sortedLibraryTags) { tag in
            Button {
              Task { await tagService.assign(tagNames: [tag.name], to: Array(batchSelection)) }
            } label: {
              tagMenuTitle(
                name: tag.name,
                usageCount: nil,
                hex: tag.colorHex,
                isSelected: false
              )
            }
          }
        }
      } label: {
        Label(L10n.string("tag_editor_library_button"), systemImage: "text.badge.plus")
      }
      .disabled(tagService.allTags.isEmpty)
    }
  }

  /// 批量选择控制菜单和提示
  ///
  /// 布局：
  /// - **左侧**：批量选择下拉菜单
  /// - **中间**：选中图片数量提示
  /// - **右侧**：Spacer 推向左对齐
  ///
  /// 菜单功能：
  /// 1. **仅当前图片**：重置选择为主图片
  /// 2. **全选**：选中所有图片
  /// 3. **分隔线**
  /// 4. **单张图片列表**：逐个勾选/取消勾选
  ///
  /// 交互逻辑：
  /// - 点击已选中的图片：取消选中（至少保留一张）
  /// - 点击未选中的图片：添加到选择集合
  /// - 显示文件名和选中状态图标
  ///
  /// 视觉设计：
  /// - 菜单标签显示选中数量
  /// - 提示文本使用次要色调和小字号
  var batchSelectionControls: some View {
    HStack(spacing: 12) {
      Menu {
        Button(L10n.string("tag_editor_batch_only_current")) {
          batchSelection = [imageURL]
        }
        Button(L10n.string("tag_editor_batch_select_all")) {
          batchSelection = Set(imageURLs)
        }
        Divider()
        ForEach(imageURLs, id: \.self) { url in
          let isSelected = batchSelection.contains(url)
          Button {
            toggleSelection(for: url)
          } label: {
            Label(
              url.lastPathComponent,
              systemImage: isSelected ? "checkmark.circle.fill" : "circle"
            )
          }
        }
      } label: {
        Label(
          String(
            format: L10n.string("tag_editor_batch_menu_label"),
            selectionCount
          ),
          systemImage: "square.stack.3d.up"
        )
      }

      Text(
        String(
          format: L10n.string("tag_editor_batch_hint"),
          selectionCount
        )
      )
      .font(.caption)
      .foregroundColor(.secondary)

      Spacer()
    }
  }

  /// 当前图片已绑定的标签列表
  ///
  /// 显示逻辑：
  /// - **标签为空**：显示提示文本"暂无标签"
  /// - **标签非空**：横向滚动的标签胶囊列表
  ///
  /// 标签胶囊功能：
  /// 1. **颜色圆点**：显示标签颜色，点击可编辑颜色
  /// 2. **标签名称**：显示标签文本
  /// 3. **删除按钮**：点击从当前图片移除该标签
  ///
  /// 交互效果：
  /// - 标签移除时执行缩放和淡出动画（.scale.combined(with: .opacity)）
  /// - 横向滚动支持查看更多标签
  ///
  /// 视觉设计：
  /// - 标签胶囊使用标签颜色的半透明背景
  /// - 空状态文本使用次要色调
  var tagList: some View {
    Group {
      if assignedTags.isEmpty {
        Text(L10n.string("tag_editor_empty"))
          .font(.footnote)
          .foregroundColor(.secondary)
          .frame(maxWidth: .infinity, alignment: .leading)
      } else {
        ScrollView(.horizontal, showsIndicators: false) {
          HStack(spacing: 8) {
            ForEach(assignedTags, id: \.id) { tag in
              let tint = Color(hexString: tag.colorHex) ?? Color.accentColor
              TagChip(
                title: tag.name,
                systemImage: "xmark.circle.fill",
                tint: tint,
                onColorTap: {
                  colorEditorColor = tint
                  colorEditorTag = tag
                }
              ) {
                Task { await tagService.remove(tagID: tag.id, from: imageURL) }
              }
              .transition(.scale.combined(with: .opacity))
            }
          }
          .padding(.vertical, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
      }
    }
  }

  /// 推荐标签区域
  ///
  /// 显示条件：推荐列表非空
  ///
  /// 布局：
  /// - **标题**："建议标签" 文本标题
  /// - **标签列表**：横向滚动的推荐标签按钮
  ///
  /// 推荐逻辑：
  /// - 基于目录热度：同目录下常用的标签
  /// - 基于作用域热度：当前选中图片集合中常用的标签
  /// - 排除已有标签：不推荐图片已有的标签
  ///
  /// 交互功能：
  /// - 点击推荐标签：添加到当前图片（单张）
  /// - 同时记录推荐选择事件，用于改进推荐算法
  ///
  /// 视觉设计：
  /// - 标题使用次要色调和小字号
  /// - 推荐按钮使用主题色半透明背景
  var recommendedSection: some View {
    Group {
      if !recommendedSuggestions.isEmpty {
        VStack(alignment: .leading, spacing: 6) {
          Text(L10n.string("tag_editor_recommend_title"))
            .font(.caption)
            .foregroundColor(.secondary)
          ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
              ForEach(recommendedSuggestions, id: \.id) { tag in
                RecommendedTagChip(tag: tag) {
                  Task {
                    await MainActor.run {
                      tagService.recordRecommendationSelection(tagID: tag.id, for: imageURL)
                    }
                    await tagService.assign(tagNames: [tag.name], to: [imageURL])
                  }
                }
              }
            }
            .padding(.vertical, 2)
          }
        }
      }
    }
  }

  /// 标签输入行
  ///
  /// 布局：
  /// - **文本框**：输入标签名称
  /// - **添加按钮**：提交输入
  /// - **提示文本**：显示批量操作的目标数量
  ///
  /// 输入功能：
  /// - 支持单个标签：直接输入名称
  /// - 支持批量标签：用逗号、分号或换行符分隔
  /// - 回车提交：.submitLabel(.done) + .onSubmit
  /// - 自动聚焦：提交后保持焦点，方便连续输入
  ///
  /// 验证规则：
  /// - 去除空白字符后非空才允许提交
  /// - 按钮状态根据输入有效性变化（颜色和禁用状态）
  ///
  /// 视觉设计：
  /// - 圆角边框文本框样式
  /// - 按钮使用填充圆形图标
  /// - 有效输入时按钮为主题色，无效时为灰色
  var inputRow: some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack(spacing: 8) {
        TextField(L10n.string("tag_editor_placeholder"), text: $tagInput)
          .textFieldStyle(.roundedBorder)
          .submitLabel(.done)
          .focused($inputFocused)
          .onSubmit { commitInput() }

        Button {
          commitInput()
        } label: {
          Image(systemName: "plus.circle.fill")
            .foregroundStyle(isInputValid ? Color.accentColor : Color.secondary.opacity(0.6))
            .font(.title3)
        }
        .buttonStyle(.plain)
        .disabled(!isInputValid)
      }

      Text(
        String(
          format: L10n.string("tag_editor_batch_hint"),
          selectionCount
        )
      )
      .font(.caption2)
      .foregroundColor(.secondary)
    }
  }

  /// 提交文本框输入
  ///
  /// 处理用户在文本框中输入的标签，支持多种分隔符。
  ///
  /// 执行流程：
  /// 1. **清理输入**：去除首尾空白字符
  /// 2. **验证非空**：空输入直接返回
  /// 3. **分隔解析**：按逗号、分号、换行符分隔
  /// 4. **清理组件**：去除每个组件的空白字符，过滤空值
  /// 5. **提交标签**：调用 taskAssign 添加标签
  /// 6. **清空输入**：清空文本框
  /// 7. **保持焦点**：重新聚焦文本框，方便连续输入
  ///
  /// 分隔符支持：
  /// - **逗号**：`,` - 最常用的分隔符
  /// - **分号**：`;` - 兼容某些输入习惯
  /// - **换行符**：`\n` - 支持多行粘贴
  ///
  /// 边界情况：
  /// - 分隔后所有组件都是空：使用原始 trimmed 字符串
  /// - 混合分隔符：正确处理所有分隔符组合
  ///
  /// 示例：
  /// - 输入 "工作,重要"  -> ["工作", "重要"]
  /// - 输入 "A; B\nC"    -> ["A", "B", "C"]
  /// - 输入 "  tag  "    -> ["tag"]
  func commitInput() {
    let trimmed = tagInput.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return }
    let separators = CharacterSet(charactersIn: ",;\n")
    let components = trimmed
      .components(separatedBy: separators)
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
    taskAssign(tags: components.isEmpty ? [trimmed] : components)
    tagInput = ""
    Task { @MainActor in
      inputFocused = true
    }
  }

  /// 批量分配标签到选中的图片
  ///
  /// 将解析出的标签名称异步提交给 TagService，添加到选中的图片。
  ///
  /// 目标图片选择：
  /// - **有选择**：使用 batchSelection 中的图片
  /// - **无选择**：只操作当前主图片
  ///
  /// 异步执行：
  /// - 使用 Task 在后台执行，不阻塞 UI
  /// - TagService 会处理数据库操作和缓存更新
  ///
  /// 使用场景：
  /// - 用户提交文本框输入
  /// - 从标签库选择标签
  ///
  /// - Parameter tags: 要分配的标签名称数组
  func taskAssign(tags: [String]) {
    guard !tags.isEmpty else { return }
    let targets = batchSelection.isEmpty ? [imageURL] : Array(batchSelection)
    Task { await tagService.assign(tagNames: tags, to: targets) }
  }

  /// 切换单张图片的批量选择状态
  ///
  /// 在批量操作菜单中勾选/取消勾选某张图片。
  ///
  /// 切换逻辑：
  /// - **已选中且只有一张**：不允许取消（至少保留一张）
  /// - **已选中且多张**：取消选中，从集合中移除
  /// - **未选中**：选中，添加到集合
  ///
  /// 最小选择限制：
  /// - 确保至少有一张图片被选中
  /// - 防止批量操作的目标为空
  ///
  /// 使用场景：
  /// - 用户在批量选择菜单中点击图片项
  ///
  /// - Parameter url: 要切换状态的图片 URL
  func toggleSelection(for url: URL) {
    if batchSelection.contains(url) {
      if batchSelection.count == 1 {
        return
      }
      batchSelection.remove(url)
    } else {
      batchSelection.insert(url)
    }
  }
}

/// 推荐标签的触发器
///
/// 用于检测推荐标签相关依赖的变化，触发重新计算推荐结果。
///
/// 实现 Hashable 以支持 .task(id:) 修饰符。
///
/// 依赖因素：
/// - **imagePath**：当前图片路径，切换图片时触发
/// - **assignmentsVersion**：标签分配缓存版本，标签变化时触发
/// - **scopedHash**：作用域标签的哈希值，作用域变化时触发
///
/// 任何一个因素变化都会导致 task 重新执行，刷新推荐标签列表。
private struct RecommendationTrigger: Hashable {
  let imagePath: String
  let assignmentsVersion: Int
  let scopedHash: Int
}

/// 标签胶囊组件
///
/// 显示已分配标签的胶囊按钮，带有颜色圆点和删除按钮。
///
/// 组件结构：
/// 1. **颜色圆点**：可点击，打开颜色编辑器
/// 2. **标签名称**：标签文本，中等粗细
/// 3. **删除按钮**：xmark 图标，点击移除标签
///
/// 视觉设计：
/// - 胶囊形状背景
/// - 使用标签颜色的 15% 透明度作为背景
/// - 横向内边距 10，纵向内边距 6
///
/// 交互功能：
/// - 点击颜色圆点：触发 onColorTap 回调
/// - 点击删除按钮：触发 action 回调
///
/// 无障碍支持：
/// - 颜色圆点有 accessibilityLabel
///
/// 使用场景：
/// - TagEditorView 的标签列表
/// - 显示图片已有的标签
private struct TagChip: View {
  /// 标签名称
  let title: String

  /// 删除按钮的 SF Symbol 图标名称
  let systemImage: String

  /// 标签颜色（用于背景和圆点）
  let tint: Color

  /// 点击颜色圆点的回调
  let onColorTap: () -> Void

  /// 点击删除按钮的回调
  let action: () -> Void

  var body: some View {
    HStack(spacing: 6) {
      Button(action: onColorTap) {
        TagColorDot(color: tint)
          .frame(width: 10, height: 10)
      }
      .buttonStyle(.plain)
      .accessibilityLabel(Text(L10n.string("tag_editor_chip_color")))

      Text(title)
        .font(.footnote.weight(.medium))
      Spacer(minLength: 4)
      Button(action: action) {
        Image(systemName: systemImage)
          .font(.system(size: 12, weight: .semibold))
      }
      .buttonStyle(.plain)
    }
    .padding(.horizontal, 10)
    .padding(.vertical, 6)
    .background(tint.opacity(0.15), in: Capsule())
  }
}

/// 颜色圆点视图
///
/// 显示一个填充颜色的圆形，带有细边框。
///
/// 视觉设计：
/// - 圆形填充指定颜色
/// - 黑色 15% 透明度的边框
/// - 用于标签颜色的视觉标识
///
/// 使用场景：
/// - TagChip 中的颜色指示器
/// - RecommendedTagChip 中的颜色标识
/// - 其他需要显示标签颜色的地方
struct TagColorDot: View {
  /// 圆点的填充颜色
  let color: Color

  var body: some View {
    Circle()
      .fill(color)
      .overlay(
        Circle()
          .strokeBorder(Color.black.opacity(0.15))
      )
  }
}

/// 推荐标签按钮
///
/// 显示推荐标签的可点击按钮，点击后将标签添加到图片。
///
/// 组件结构：
/// 1. **颜色圆点**：8x8 的小圆点，显示标签颜色
/// 2. **标签名称**：小字号的标签文本
///
/// 视觉设计：
/// - 胶囊形状背景
/// - 主题色 12% 透明度背景
/// - 横向内边距 10，纵向内边距 6
/// - 与 TagChip 类似但更轻量
///
/// 交互功能：
/// - 点击按钮：触发 action 回调（添加标签到图片）
///
/// 使用场景：
/// - TagEditorView 的推荐标签区域
/// - 显示推荐给用户的标签选项
struct RecommendedTagChip: View {
  /// 推荐的标签记录
  let tag: TagRecord

  /// 点击按钮的回调（添加标签）
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      HStack(spacing: 6) {
        TagColorDot(color: Color(hexString: tag.colorHex) ?? .accentColor)
          .frame(width: 8, height: 8)
        Text(tag.name)
          .font(.footnote)
          .foregroundColor(.primary)
      }
      .padding(.horizontal, 10)
      .padding(.vertical, 6)
      .background(Color.accentColor.opacity(0.12), in: Capsule())
    }
    .buttonStyle(.plain)
  }
}

/// 标签颜色编辑 Sheet
///
/// 弹出式对话框，用于编辑标签的颜色。
///
/// 功能特点：
/// 1. **颜色选择**：使用系统 ColorPicker 选择颜色
/// 2. **保存颜色**：将选中的颜色保存到标签
/// 3. **清除颜色**：移除标签的自定义颜色
/// 4. **取消操作**：关闭对话框不保存
///
/// 布局结构：
/// - **标题**：显示"为 [标签名] 选择颜色"
/// - **颜色选择器**：系统 ColorPicker（不支持透明度）
/// - **按钮行**：清除、取消、保存
///
/// 按钮功能：
/// - **清除**：调用 onClear 并关闭
/// - **取消**：直接关闭，不执行任何操作
/// - **保存**：调用 onSave 传递选中的颜色，然后关闭
///
/// 视觉设计：
/// - 标题使用 headline 字体
/// - 颜色选择器隐藏标签（.labelsHidden()）
/// - 保存按钮使用 .borderedProminent 样式
/// - 最小宽度 320
///
/// 使用场景：
/// - 用户在 TagEditorView 中点击标签的颜色圆点
/// - TagChip 的 onColorTap 回调触发
private struct TagColorEditorSheet: View {
  /// 要编辑颜色的标签
  let tag: TagRecord

  /// 保存颜色的回调
  let onSave: (Color) -> Void

  /// 清除颜色的回调
  let onClear: () -> Void

  /// 环境变量：用于关闭 sheet
  @Environment(\.dismiss) private var dismiss

  /// 当前选中的颜色
  @State private var color: Color

  /// 初始化颜色编辑器
  ///
  /// - Parameters:
  ///   - tag: 要编辑的标签
  ///   - initialColor: 初始颜色（标签当前颜色）
  ///   - onSave: 保存颜色的回调
  ///   - onClear: 清除颜色的回调
  init(tag: TagRecord, initialColor: Color, onSave: @escaping (Color) -> Void, onClear: @escaping () -> Void) {
    self.tag = tag
    self.onSave = onSave
    self.onClear = onClear
    _color = State(initialValue: initialColor)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text(String(format: L10n.string("tag_editor_color_sheet_title"), tag.name))
        .font(.headline)

      ColorPicker(L10n.string("tag_settings_color_picker_label"), selection: $color, supportsOpacity: false)
        .labelsHidden()

      HStack {
        Button(L10n.string("tag_editor_color_sheet_clear")) {
          onClear()
          dismiss()
        }
        Spacer()
        Button(L10n.key("cancel_button")) {
          dismiss()
        }
        Button(L10n.string("tag_editor_color_sheet_save")) {
          onSave(color)
          dismiss()
        }
        .buttonStyle(.borderedProminent)
      }
    }
    .padding()
    .frame(minWidth: 320)
  }
}
