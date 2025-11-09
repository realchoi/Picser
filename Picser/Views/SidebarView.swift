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
  /// 是否显示 TagFilterPanel
  let showingTagFilter: Bool
  /// 切换筛选面板的回调，由外层控制状态
  let toggleTagFilter: () -> Void
  let onSelect: (URL) -> Void
  @EnvironmentObject var tagService: TagService

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
  /// 顶部筛选开关，附带当前条件摘要
  var filterHeader: some View {
    VStack(alignment: .leading, spacing: 8) {
      Button {
        toggleTagFilter()
      } label: {
        HStack {
          Label(
            showingTagFilter
              ? L10n.string("tag_filter_hide_button")
              : L10n.string("tag_filter_show_button"),
            systemImage: showingTagFilter ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle"
          )
          Spacer()
          if tagService.activeFilter.isActive {
            Text(selectionSummary)
              .font(.caption)
              .foregroundColor(.secondary)
          }
        }
      }
      .buttonStyle(.plain)
      .padding(.horizontal, 10)
      .padding(.top, 8)

      if showingTagFilter {
        TagFilterPanel()
          .padding(.bottom, 6)
      }
    }
    .background(
      showingTagFilter
        ? AnyView(
          RoundedRectangle(cornerRadius: 0)
            .fill(Color.clear)
            .overlay(alignment: .bottom) {
              Divider()
                .padding(.horizontal, 8)
            }
        )
        : AnyView(EmptyView())
    )
    .padding(.horizontal, 6)
  }

  /// 显示当前选中的标签数量或“无筛选”
  var selectionSummary: String {
    let count = tagService.activeFilter.tagIDs.count
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
