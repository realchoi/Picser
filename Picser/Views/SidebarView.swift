//
//  SidebarView.swift
//
//  Extracted from ContentView to keep it lean.
//

import SwiftUI

/// 侧边栏视图，显示图片缩略图列表并允许选择。
struct SidebarView: View {
  let imageURLs: [URL]
  let selectedImageURL: URL?
  let onSelect: (URL) -> Void

  var body: some View {
    ScrollViewReader { proxy in
      List {
        ForEach(imageURLs, id: \.self) { url in
          ZStack(alignment: .bottomLeading) {
            ThumbnailImageView(url: url, height: 80)
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
        }
      }
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
