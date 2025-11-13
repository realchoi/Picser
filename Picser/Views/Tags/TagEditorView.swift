//
//  TagEditorView.swift
//
//  Created by Eric Cai on 2025/11/08.
//

import SwiftUI

/// 详情区域底部的标签编辑器，支持对多张图片批量打标签。
struct TagEditorView: View {
  let imageURL: URL
  let imageURLs: [URL]

  @EnvironmentObject var tagService: TagService
  @State private var tagInput: String = ""
  @FocusState private var inputFocused: Bool
  @State private var batchSelection: Set<URL> = []
  @State private var colorEditorTag: TagRecord?
  @State private var colorEditorColor: Color = .accentColor
  @State private var recommendedSuggestions: [TagRecord] = []

  /// 已应用在当前主图片上的标签（按名称排序）
  private var assignedTags: [TagRecord] {
    tagService
      .tags(for: imageURL)
      .sorted {
        $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
      }
  }

  /// 文本框输入是否可以提交
  private var isInputValid: Bool {
    !tagInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  /// 批量选中的图片数，至少为 1（当前图片）
  private var selectionCount: Int {
    max(batchSelection.count, 1)
  }

  /// 全部标签列表，按名称排序以便检索
  private var sortedLibraryTags: [TagRecord] {
    tagService.allTagsSortedByName
  }

  private var recommendationTrigger: RecommendationTrigger {
    RecommendationTrigger(
      imagePath: imageURL.path,
      assignmentsVersion: tagService.assignmentsVersion,
      scopedHash: tagService.scopedTags.hashValue
    )
  }

  init(imageURL: URL, imageURLs: [URL]) {
    let normalizedPrimary = imageURL.standardizedFileURL
    self.imageURL = normalizedPrimary
    self.imageURLs = imageURLs.map { $0.standardizedFileURL }
    _batchSelection = State(initialValue: [normalizedPrimary])
  }

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

private extension TagEditorView {
  /// 标题行 + 全局标签库按钮
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

  /// 控制批量选中图片的菜单与提示
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

  /// 显示当前图片已绑定的标签，可快速移除或改色
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

  /// 推荐标签列表，鼓励复用常用标签
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

  /// 文本输入 + 快捷按钮行
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

  /// 把解析出的标签串行下发给 TagService
  func taskAssign(tags: [String]) {
    guard !tags.isEmpty else { return }
    let targets = batchSelection.isEmpty ? [imageURL] : Array(batchSelection)
    Task { await tagService.assign(tagNames: tags, to: targets) }
  }

  /// 切换单张图片是否参与批量打标签
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

private struct RecommendationTrigger: Hashable {
  let imagePath: String
  let assignmentsVersion: Int
  let scopedHash: Int
}

/// 带颜色指示与删除按钮的标签胶囊
private struct TagChip: View {
  let title: String
  let systemImage: String
  let tint: Color
  let onColorTap: () -> Void
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

/// 通用颜色圆点
struct TagColorDot: View {
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

/// 推荐标签按钮，点击即可添加
struct RecommendedTagChip: View {
  let tag: TagRecord
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

/// 弹出式颜色编辑器，支持保存与清除
private struct TagColorEditorSheet: View {
  let tag: TagRecord
  let onSave: (Color) -> Void
  let onClear: () -> Void

  @Environment(\.dismiss) private var dismiss
  @State private var color: Color

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
