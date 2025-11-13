//
//  TagColorIcon.swift
//  Picser
//
//  标签颜色图标组件
//  在标签相关的菜单和列表中显示彩色圆点，用于视觉区分不同标签。
//

import SwiftUI

/// 标签颜色图标
///
/// 显示标签的颜色标识，使用彩色圆点（●）表示。
///
/// 功能特点：
/// - **彩色圆点**：使用 Unicode 字符 ● 作为图标
/// - **自定义颜色**：支持通过 HEX 字符串设置颜色
/// - **默认颜色**：没有自定义颜色时使用系统主题色（accentColor）
///
/// 使用场景：
/// - 标签列表中显示标签颜色
/// - 标签筛选面板中的标签图标
/// - 标签编辑器中的颜色预览
/// - 下拉菜单中的标签项
///
/// 示例：
/// ```swift
/// TagColorIcon(hex: "#FF0000")  // 红色圆点
/// TagColorIcon(hex: nil)         // 使用主题色
/// ```
struct TagColorIcon: View {
  /// 标签颜色的 HEX 字符串（可选，格式为 #RRGGBB）
  /// nil 表示使用系统默认的主题色
  let hex: String?

  var body: some View {
    Text("●")
      .font(.system(size: 10, weight: .bold))
      .foregroundColor(Color(hexString: hex) ?? Color.accentColor)
  }
}

/// 组装标签菜单项的标题文本
///
/// 创建包含颜色圆点、标签名称、使用次数和选中标记的复合文本。
///
/// 文本组成：
/// 1. **颜色圆点**：● 字符，显示标签颜色
/// 2. **标签名称**：标签的名称文本
/// 3. **使用次数**：可选的使用次数统计（格式：name (count)）
/// 4. **选中标记**：可选的 ✓ 符号，表示当前项被选中
///
/// 颜色逻辑：
/// - **圆点颜色**：使用标签的自定义颜色，没有则使用主题色
/// - **名称颜色**：使用主色调（.primary）
/// - **选中标记颜色**：使用次要色调（.secondary）
///
/// 使用场景：
/// - 标签选择下拉菜单
/// - 标签筛选面板的菜单项
/// - 标签批量操作菜单
///
/// 示例：
/// ```swift
/// // 未选中的标签，显示使用次数
/// tagMenuTitle(name: "工作", usageCount: 15, hex: "#FF0000", isSelected: false)
/// // 结果：● 工作 (15)
///
/// // 已选中的标签，不显示使用次数
/// tagMenuTitle(name: "重要", usageCount: nil, hex: nil, isSelected: true)
/// // 结果：● 重要 ✓
/// ```
///
/// - Parameters:
///   - name: 标签名称
///   - usageCount: 使用次数（可选），传入 nil 则不显示次数
///   - hex: 标签颜色的 HEX 字符串（可选）
///   - isSelected: 是否选中（选中时显示 ✓ 标记）
/// - Returns: 组合后的 Text 视图，可直接用于 Menu 或 Picker
func tagMenuTitle(name: String, usageCount: Int?, hex: String?, isSelected: Bool) -> Text {
  // 解析颜色，没有自定义颜色时使用系统主题色
  let tint = Color(hexString: hex) ?? Color.accentColor
  // 组装标签名称和使用次数（如果有）
  let label = usageCount.map { "\(name) (\($0))" } ?? name

  // 拼接彩色圆点
  var text = Text("● ")
    .foregroundColor(tint)

  // 拼接标签名称
  text = text + Text(label)
    .foregroundColor(.primary)

  // 拼接选中标记（如果需要）
  if isSelected {
    text = text + Text(" ✓")
      .foregroundColor(.secondary)
  }

  return text
}
