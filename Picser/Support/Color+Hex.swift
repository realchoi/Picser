//
//  Color+Hex.swift
//
//  Created by Eric Cai on 2025/11/09.
//

import SwiftUI

/// 跨平台颜色类型别名
///
/// 统一 macOS 和 iOS/tvOS 的颜色类型，简化跨平台代码。
#if os(macOS)
import AppKit
/// macOS 使用 NSColor
typealias PlatformColor = NSColor
#else
import UIKit
/// iOS/tvOS 使用 UIColor
typealias PlatformColor = UIColor
#endif

extension Color {
  /// 通过 HEX 字符串初始化颜色
  ///
  /// 支持的格式：
  /// - 6 位：#RRGGBB 或 RRGGBB（不含 alpha）
  /// - 8 位：#RRGGBBAA 或 RRGGBBAA（包含 alpha）
  ///
  /// 容错处理：
  /// - 自动去除前缀 # 和空白字符
  /// - 大小写不敏感
  ///
  /// 示例：
  /// ```swift
  /// Color(hexString: "#FF0000")    // 红色
  /// Color(hexString: "00FF00")     // 绿色
  /// Color(hexString: "#0000FFCC")  // 半透明蓝色
  /// ```
  ///
  /// - Parameter hexString: HEX 颜色字符串（可选）
  /// - Returns: 颜色对象，格式无效时返回 nil
  init?(hexString: String?) {
    guard
      let hexString,
      !hexString.isEmpty
    else {
      return nil
    }
    var value = hexString.trimmingCharacters(in: .whitespacesAndNewlines)

    // 容错处理：兼容用户输入的 #前缀
    if value.hasPrefix("#") {
      value.removeFirst()
    }

    // 只支持 6 位（RGB）或 8 位（RGBA）
    guard value.count == 6 || value.count == 8 else {
      return nil
    }

    // 解析十六进制数值
    var hexValue: UInt64 = 0
    guard Scanner(string: value).scanHexInt64(&hexValue) else {
      return nil
    }

    // 提取 RGBA 分量
    let hasAlpha = value.count == 8
    let r = Double((hexValue >> (hasAlpha ? 24 : 16)) & 0xFF) / 255.0
    let g = Double((hexValue >> (hasAlpha ? 16 : 8)) & 0xFF) / 255.0
    let b = Double((hexValue >> (hasAlpha ? 8 : 0)) & 0xFF) / 255.0
    let a = hasAlpha ? Double(hexValue & 0xFF) / 255.0 : 1.0

    self.init(red: r, green: g, blue: b, opacity: a)
  }

  /// 将颜色转换为 HEX 字符串
  ///
  /// 输出格式：#RRGGBB（不包含 alpha 通道）
  ///
  /// 示例：
  /// ```swift
  /// Color.red.hexString()  // "#FF0000"
  /// Color.green.hexString()  // "#00FF00"
  /// ```
  ///
  /// - Returns: HEX 字符串，转换失败时返回 nil
  func hexString() -> String? {
    guard let components = rgbaComponents() else { return nil }
    // 组件值已经是 0-255 的整数，格式化时统一补零为 2 位
    return String(format: "#%02X%02X%02X", components.r, components.g, components.b)
  }

  /// 提取 RGBA 颜色分量
  ///
  /// 跨平台实现：
  /// - **macOS**：需要先转换到 sRGB 色彩空间，否则会读到错误的值
  /// - **iOS/tvOS**：直接读取 RGBA 分量即可
  ///
  /// - Returns: RGBA 分量元组，r/g/b 范围 0-255，a 范围 0.0-1.0
  ///           转换失败时返回 nil
  private func rgbaComponents() -> (r: Int, g: Int, b: Int, a: CGFloat)? {
    #if os(macOS)
    // macOS 需要显式转换到 sRGB 色彩空间
    // 某些颜色（如系统颜色）可能在其他色彩空间，直接读取会得到 0
    guard let platformColor = PlatformColor(self).usingColorSpace(.sRGB) else { return nil }
    let r = Int(round(platformColor.redComponent * 255.0))
    let g = Int(round(platformColor.greenComponent * 255.0))
    let b = Int(round(platformColor.blueComponent * 255.0))
    let a = platformColor.alphaComponent
    return (r, g, b, a)
    #else
    // iOS/tvOS 直接读取 RGBA 分量
    let platformColor = PlatformColor(self)
    var r: CGFloat = 0
    var g: CGFloat = 0
    var b: CGFloat = 0
    var a: CGFloat = 0
    // 读取失败时返回 nil（例如某些特殊颜色模式）
    guard platformColor.getRed(&r, green: &g, blue: &b, alpha: &a) else { return nil }
    return (
      Int(round(r * 255.0)),
      Int(round(g * 255.0)),
      Int(round(b * 255.0)),
      a
    )
    #endif
  }
}

extension String {
  /// 归一化 HEX 颜色字符串
  ///
  /// 规范化处理：
  /// 1. 去除首尾空白字符
  /// 2. 移除 # 前缀（如果有）
  /// 3. 转换为大写
  /// 4. 验证长度（6 或 8 位）
  /// 5. 验证所有字符都是十六进制数字
  /// 6. 添加 # 前缀
  ///
  /// 用途：
  /// - 比较颜色字符串（忽略格式差异）
  /// - 存储到数据库前的格式统一
  /// - 颜色筛选功能
  ///
  /// 示例：
  /// ```swift
  /// "ff0000".normalizedHexColor()    // "#FF0000"
  /// " #FF0000 ".normalizedHexColor() // "#FF0000"
  /// "#ff0000aa".normalizedHexColor() // "#FF0000AA"
  /// "invalid".normalizedHexColor()   // nil
  /// ```
  ///
  /// - Returns: 归一化后的 HEX 字符串（#RRGGBB 或 #RRGGBBAA），无效时返回 nil
  func normalizedHexColor() -> String? {
    var value = trimmingCharacters(in: .whitespacesAndNewlines)
    guard !value.isEmpty else { return nil }

    // 移除 # 前缀
    if value.hasPrefix("#") {
      value.removeFirst()
    }
    guard !value.isEmpty else { return nil }

    // 验证长度
    guard value.count == 6 || value.count == 8 else { return nil }

    // 转换为大写并验证字符
    let uppercase = value.uppercased()
    guard uppercase.allSatisfy(\.isHexDigit) else { return nil }

    // 添加 # 前缀
    return "#\(uppercase)"
  }
}

extension Optional where Wrapped == String {
  /// 可选字符串的 HEX 归一化
  ///
  /// 便捷方法，处理可选类型的 HEX 字符串。
  ///
  /// 示例：
  /// ```swift
  /// let color: String? = "#FF0000"
  /// color.normalizedHexColor()  // "#FF0000"
  ///
  /// let empty: String? = nil
  /// empty.normalizedHexColor()  // nil
  /// ```
  ///
  /// - Returns: 归一化后的 HEX 字符串，原值为 nil 或格式无效时返回 nil
  func normalizedHexColor() -> String? {
    switch self {
    case let .some(value):
      return value.normalizedHexColor()
    case .none:
      return nil
    }
  }
}
