//
//  SettingsWindowResizer.swift
//
//  Created by Eric Cai on 2025/10/29.
//

import AppKit
import SwiftUI

/// 使用 AppKit 直接驱动设置窗口的内容高度
struct SettingsWindowResizer: NSViewRepresentable {
  /// 目标内容高度（不含窗口边框）
  let targetContentHeight: CGFloat
  /// 最小内容高度，用于约束窗口尺寸
  let minContentHeight: CGFloat
  /// 最大内容高度，用于约束窗口尺寸
  let maxContentHeight: CGFloat
  /// 是否启用平滑动画
  let animate: Bool
  /// 动画时长，便于与 SwiftUI 状态更新保持一致
  let animationDuration: TimeInterval

  init(
    targetContentHeight: CGFloat,
    minContentHeight: CGFloat = 360,
    maxContentHeight: CGFloat = 720,
    animate: Bool = true,
    animationDuration: TimeInterval = 0.25
  ) {
    self.targetContentHeight = targetContentHeight
    self.minContentHeight = minContentHeight
    self.maxContentHeight = maxContentHeight
    self.animate = animate
    self.animationDuration = animationDuration
  }

  /// 创建协调器，用于缓存最近一次应用的高度
  func makeCoordinator() -> Coordinator {
    Coordinator()
  }

  /// 创建承载视图，实际只需一个空壳即可拿到窗口引用
  func makeNSView(context: Context) -> NSView {
    let view = NSView(frame: .zero)
    view.postsFrameChangedNotifications = false
    return view
  }

  /// 每当 SwiftUI 更新目标高度时，向窗口下发新的内容尺寸
  func updateNSView(_ nsView: NSView, context: Context) {
    DispatchQueue.main.async {
      guard let window = nsView.window else { return }
      guard targetContentHeight > 0 else { return }

      let clampedHeight = max(minContentHeight, min(targetContentHeight, maxContentHeight))
      let currentContentHeight = window.contentLayoutRect.height

      if let lastHeight = context.coordinator.lastAppliedHeight,
         abs(lastHeight - clampedHeight) < 0.5 {
        return
      }

      if abs(currentContentHeight - clampedHeight) < 0.5 {
        context.coordinator.lastAppliedHeight = clampedHeight
        return
      }

      let currentFrame = window.frame
      var targetContentSize = window.contentLayoutRect.size
      targetContentSize.height = clampedHeight

      var targetFrame = window.frameRect(forContentRect: NSRect(origin: .zero, size: targetContentSize))
      targetFrame.origin.x = currentFrame.origin.x
      targetFrame.origin.y = currentFrame.maxY - targetFrame.size.height

      context.coordinator.lastAppliedHeight = clampedHeight

      if animate {
        NSAnimationContext.runAnimationGroup { ctx in
          ctx.duration = animationDuration
          window.animator().setFrame(targetFrame, display: true)
        }
      } else {
        window.setFrame(targetFrame, display: true)
      }
    }
  }

  /// 协调器用于记录最近一次应用的高度，避免重复动画
  final class Coordinator {
    var lastAppliedHeight: CGFloat?
  }
}
