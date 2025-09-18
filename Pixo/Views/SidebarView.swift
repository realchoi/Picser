//
//  SidebarView.swift
//  Pixo
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
      }
    }
  }
}
