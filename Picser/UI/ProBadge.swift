//
//  ProBadge.swift
//
//  PRO 标识组件，用于标识需要订阅才能使用的功能
//

import SwiftUI

/// PRO 功能标识修饰器
///
/// 在图标右下角显示小型 PRO 标识，仅当用户未订阅时显示。
struct ProBadgeModifier: ViewModifier {
  let isEntitled: Bool

  func body(content: Content) -> some View {
    if isEntitled {
      content
    } else {
      content
        .overlay(alignment: .bottomTrailing) {
          ProBadge()
            .offset(x: 6, y: 4)
        }
    }
  }
}

/// 小型 PRO 标识
///
/// 使用 "PRO" 文字胶囊设计，简洁现代，配合金色渐变。
struct ProBadge: View {
  var body: some View {
    Text("PRO")
      .font(.system(size: 6, weight: .black, design: .rounded))
      .fixedSize()
      .foregroundStyle(.white)
      .padding(.horizontal, 3)
      .padding(.vertical, 1)
      .background(
        RoundedRectangle(cornerRadius: 3)
          .fill(
            LinearGradient(
              colors: [
                Color(red: 1.0, green: 0.85, blue: 0.3), // 金色高光
                Color(red: 1.0, green: 0.6, blue: 0.0)   // 深金色阴影
              ],
              startPoint: .topLeading,
              endPoint: .bottomTrailing
            )
          )
      )
      .overlay(
        RoundedRectangle(cornerRadius: 3)
          .strokeBorder(.white, lineWidth: 1)
      )
      .shadow(color: .black.opacity(0.1), radius: 1, x: 0, y: 1)
  }
}

extension View {
  /// 为视图添加 PRO 标识（仅未订阅时显示）
  func proBadge(isEntitled: Bool) -> some View {
    modifier(ProBadgeModifier(isEntitled: isEntitled))
  }
}

#Preview {
  VStack(spacing: 20) {
    // 未订阅状态
    Image(systemName: "crop")
      .font(.title)
      .proBadge(isEntitled: false)
    
    // 已订阅状态
    Image(systemName: "crop")
      .font(.title)
      .proBadge(isEntitled: true)
  }
  .padding()
}

