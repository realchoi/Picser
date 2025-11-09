//
//  TagColorIcon.swift
//  Picser
//
//  Shared color swatch used across tag-related menus.
//

import SwiftUI

/// 标签列表中复用的彩色圆点
struct TagColorIcon: View {
  let hex: String?
  var body: some View {
    Text("●")
      .font(.system(size: 10, weight: .bold))
      .foregroundColor(Color(hexString: hex) ?? Color.accentColor)
  }
}

/// 组装下拉菜单标题，附带彩色圆点与使用次数
func tagMenuTitle(name: String, usageCount: Int?, hex: String?, isSelected: Bool) -> Text {
  let tint = Color(hexString: hex) ?? Color.accentColor  // 没有自定义颜色时退回主题色
  let label = usageCount.map { "\(name) (\($0))" } ?? name
  var text = Text("● ")
    .foregroundColor(tint)
  text = text + Text(label)
    .foregroundColor(.primary)
  if isSelected {
    text = text + Text(" ✓")
      .foregroundColor(.secondary)
  }
  return text
}
