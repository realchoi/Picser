//
//  Color+Hex.swift
//
//  Created by Eric Cai on 2025/11/09.
//

import SwiftUI

#if os(macOS)
import AppKit
typealias PlatformColor = NSColor
#else
import UIKit
typealias PlatformColor = UIColor
#endif

extension Color {
  /// 通过 6/8 位 HEX 字符串初始化颜色
  init?(hexString: String?) {
    guard
      let hexString,
      !hexString.isEmpty
    else {
      return nil
    }
    var value = hexString.trimmingCharacters(in: .whitespacesAndNewlines)
    // 容错处理：兼容用户输入的 #
    if value.hasPrefix("#") {
      value.removeFirst()
    }
    guard value.count == 6 || value.count == 8 else {
      return nil
    }
    var hexValue: UInt64 = 0
    guard Scanner(string: value).scanHexInt64(&hexValue) else {
      return nil
    }
    let hasAlpha = value.count == 8
    let r = Double((hexValue >> (hasAlpha ? 24 : 16)) & 0xFF) / 255.0
    let g = Double((hexValue >> (hasAlpha ? 16 : 8)) & 0xFF) / 255.0
    let b = Double((hexValue >> (hasAlpha ? 8 : 0)) & 0xFF) / 255.0
    let a = hasAlpha ? Double(hexValue & 0xFF) / 255.0 : 1.0
    self.init(red: r, green: g, blue: b, opacity: a)
  }

  /// 将颜色转换为 #RRGGBB 字符串
  func hexString() -> String? {
    guard let components = rgbaComponents() else { return nil }
    // 组件值已经是 0-255 的整数，格式化时统一补零
    return String(format: "#%02X%02X%02X", components.r, components.g, components.b)
  }

  private func rgbaComponents() -> (r: Int, g: Int, b: Int, a: CGFloat)? {
    #if os(macOS)
    // macOS 需要显式转换到 sRGB，否则会读到 0 值
    guard let platformColor = PlatformColor(self).usingColorSpace(.sRGB) else { return nil }
    let r = Int(round(platformColor.redComponent * 255.0))
    let g = Int(round(platformColor.greenComponent * 255.0))
    let b = Int(round(platformColor.blueComponent * 255.0))
    let a = platformColor.alphaComponent
    return (r, g, b, a)
    #else
    let platformColor = PlatformColor(self)
    var r: CGFloat = 0
    var g: CGFloat = 0
    var b: CGFloat = 0
    var a: CGFloat = 0
    // iOS/tvOS 直接读取 RGBA，失败则返回空
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
