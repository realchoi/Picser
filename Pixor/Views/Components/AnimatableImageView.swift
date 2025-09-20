//
//  AnimatableImageView.swift
//  Pixor
//
//  Extracted from ZoomableImageView to isolate NSImageView wrapper.
//

import AppKit
import SwiftUI

/// 使用 NSViewRepresentable 封装 NSImageView，以支持 GIF 动画播放
struct AnimatableImageView: NSViewRepresentable {
  let image: NSImage

  func makeNSView(context: Context) -> NSImageView {
    let imageView = NSImageView()
    imageView.image = image
    imageView.imageScaling = .scaleProportionallyUpOrDown
    imageView.animates = true  // 关键：允许播放动画
    imageView.isEditable = false
    imageView.setContentCompressionResistancePriority(.fittingSizeCompression, for: .horizontal)
    imageView.setContentCompressionResistancePriority(.fittingSizeCompression, for: .vertical)
    return imageView
  }

  func updateNSView(_ nsView: NSImageView, context: Context) {
    nsView.image = image
  }
}

