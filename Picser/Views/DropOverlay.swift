//
//  DropOverlay.swift
//
//  Extracted from ContentView to keep it lean.
//

import SwiftUI

/// 拖拽覆盖视图，显示拖拽提示。
struct DropOverlay: View {
  var body: some View {
    ZStack {
      // 半透明蒙层
      Color.black.opacity(0.12)
        .ignoresSafeArea()

      // 中心提示卡片
      VStack(spacing: 8) {
        Image(systemName: "square.and.arrow.down.on.square")
          .font(.system(size: 36, weight: .medium))
          .foregroundStyle(Color.accentColor)
        Text(l10n: "drop_overlay_title")
          .font(.title3)
          .bold()
        Text(l10n: "drop_overlay_subtitle")
          .font(.callout)
          .foregroundStyle(.secondary)
      }
      .padding(20)
      .background(
        .regularMaterial,
        in: RoundedRectangle(cornerRadius: 16, style: .continuous)
      )
      .overlay(
        RoundedRectangle(cornerRadius: 16, style: .continuous)
          .stroke(Color.accentColor.opacity(0.8), style: StrokeStyle(lineWidth: 2, dash: [8, 6]))
      )
      .shadow(radius: 12)
    }
  }
}

