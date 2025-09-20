//
//  RecentMenuItemView.swift
//  Pixor
//
//  在菜单中展示最近打开项的文件夹名与完整路径，以单行文字实现轻量样式。
//

import SwiftUI
import AppKit

/// “最近打开”菜单条目的标签视图，将路径追加在名称之后，并使用次要颜色弱化
struct RecentMenuItemView: View {
  let folderName: String
  let fullPath: String

  private var nameFont: Font { Font(NSFont.menuFont(ofSize: 0)) }
  private var pathFont: Font { Font(NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)) }

  var body: some View {
    label
      .lineLimit(1)
      .truncationMode(.middle)
      .help(fullPath)
  }

  /// 组合主名称与路径的文字效果
  private var label: Text {
    let nameText = Text(folderName)
      .font(nameFont)
      .foregroundStyle(Color.primary)

    let spacer = Text("  ")
      .font(nameFont)
      .foregroundStyle(Color.secondary)

    let pathText = Text(fullPath)
      .font(pathFont)
      .foregroundStyle(Color.secondary)

    return nameText + spacer + pathText
  }
}

#Preview {
  VStack(alignment: .leading, spacing: 12) {
    RecentMenuItemView(folderName: "Projects", fullPath: "/Users/eric/Projects/Pixor")
    RecentMenuItemView(folderName: "相册", fullPath: "/Volumes/Data/Photos/Trips/2025/Sydney Harbour Bridge")
  }
  .padding()
  .frame(width: 380)
}
