//
//  SidebarView.swift
//
//  Extracted from ContentView to keep it lean.
//

import SwiftUI

/// 侧边栏视图，显示图片缩略图列表并允许选择。
/// 左侧缩略图列表，新增标签筛选开关
struct SidebarView: View {
  let imageURLs: [URL]
  let selectedImageURL: URL?
  @Binding var showingFilterPopover: Bool
  let onSelect: (URL) -> Void
  let onRequestBatchDeletion: () -> Void  // 批量删除回调
  let isFilteringImages: Bool  // 是否正在筛选图片
  let onRequestUpgrade: (UpgradePromptContext) -> Void  // 升级提示回调
  @EnvironmentObject var tagService: TagService
  @EnvironmentObject var purchaseManager: PurchaseManager

  private enum LayoutMetrics {
    static let thumbnailWidth: CGFloat = 220
  }

  var body: some View {
    ScrollViewReader { proxy in
      VStack(spacing: 0) {
        filterHeader

        // 缩略图列表维持原先交互，但宽度固定避免 TagFilter 面板挤压
        List {
          ForEach(imageURLs, id: \.self) { url in
            ZStack(alignment: .bottomLeading) {
              ThumbnailImageView(url: url, height: 80)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(width: LayoutMetrics.thumbnailWidth, alignment: .leading)
                .cornerRadius(8)

              Text(url.lastPathComponent)
                .font(.caption)
                .lineLimit(1)
                .foregroundColor(.white)
                .padding(4)
                .background(Color.black.opacity(0.6))
                .cornerRadius(4)
                .padding(4)
            }
            .padding(.vertical, 2)
            .contentShape(Rectangle())
            .onTapGesture { onSelect(url) }
            .overlay(
              RoundedRectangle(cornerRadius: 8)
                .stroke((selectedImageURL == url) ? Color.accentColor : Color.clear, lineWidth: 2)
            )
            .animation(Motion.Anim.standard, value: selectedImageURL)
            .id(url)
            .listRowInsets(EdgeInsets(top: 4, leading: 4, bottom: 4, trailing: 4))
          }
        }
        .padding(.top, 6)
        .onAppear {
          scrollToSelected(using: proxy, animated: false)
        }
        .onChange(of: selectedImageURL) { _, _ in
          scrollToSelected(using: proxy, animated: true)
        }
        .onChange(of: imageURLs) { _, _ in
          scrollToSelected(using: proxy, animated: false)
        }
      }
    }
  }
}

private extension SidebarView {
  /// 顶部筛选按钮，通过 Popover 展示筛选器
  var filterHeader: some View {
    VStack(alignment: .leading, spacing: 8) {
      Button {
        if purchaseManager.isEntitled {
          showingFilterPopover.toggle()
        } else {
          onRequestUpgrade(.tags)
        }
      } label: {
        HStack {
          Label(
            L10n.string("tag_filter_show_button"),
            systemImage: showingFilterPopover ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle"
          )
          Spacer()
          if tagService.activeFilter.isActive {
            Text(selectionSummary)
              .font(.caption)
              .foregroundColor(.secondary)
            // 清除筛选按钮，省去用户打开面板的步骤
            Button {
              tagService.clearFilter()
            } label: {
              Image(systemName: "xmark.circle.fill")
                .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .help(L10n.string("tag_filter_clear_button"))
          }
        }
      }
      .buttonStyle(.plain)
      .padding(.horizontal, 10)
      .padding(.top, 8)
      .popover(isPresented: $showingFilterPopover, arrowEdge: .bottom) {
        TagFilterPanel(
          visibleImageCount: imageURLs.count,
          onRequestBatchDeletion: onRequestBatchDeletion,
          isFilteringImages: isFilteringImages
        )
        .frame(width: 340)
        .padding()
      }

      Divider()
        .padding(.horizontal, 8)
        .padding(.top, 2)
    }
    .padding(.horizontal, 6)
  }

  /// 显示当前筛选条件下匹配的标签数量
  ///
  /// 计算逻辑：
  /// - 直接选中的标签 ID 数量
  /// - 加上通过颜色筛选匹配的标签数量（从 scopedTags 中提取）
  /// - 两者取并集后去重，避免重复计数
  var selectionSummary: String {
    let filter = tagService.activeFilter
    
    // 直接选中的标签 ID
    var matchedTagIDs = filter.tagIDs
    
    // 通过颜色筛选匹配的标签
    if !filter.colorHexes.isEmpty {
      let colorMatchedIDs = tagService.scopedTags
        .filter { tag in
          guard let hex = tag.colorHex?.normalizedHexColor() else { return false }
          return filter.colorHexes.contains(hex)
        }
        .map(\.id)
      matchedTagIDs.formUnion(colorMatchedIDs)
    }
    
    let count = matchedTagIDs.count
    if count == 0 {
      return L10n.string("tag_filter_selection_summary_none")
    }
    return String(format: L10n.string("tag_filter_selection_summary_some"), count)
  }
}

private extension SidebarView {
  /// 将当前选中图片滚动到可视区域中央，便于用户确认切换。
  func scrollToSelected(using proxy: ScrollViewProxy, animated: Bool) {
    guard let target = selectedImageURL, imageURLs.contains(target) else { return }

    let performScroll = {
      proxy.scrollTo(target, anchor: .center)
    }

    DispatchQueue.main.async {
      if animated {
        withAnimation(Motion.Anim.standard) {
          performScroll()
        }
      } else {
        performScroll()
      }
    }
  }
}
