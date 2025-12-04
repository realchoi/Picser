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
/// 使用紧凑的星形设计，避免文字被截断问题。
struct ProBadge: View {
  var body: some View {
    Image(systemName: "star.fill")
      .font(.system(size: 8, weight: .bold))
      .foregroundStyle(.white)
      .padding(2)
      .background(
        Circle()
          .fill(Color.orange.gradient)
      )
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

