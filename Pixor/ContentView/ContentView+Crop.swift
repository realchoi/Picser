//
//  ContentView+Crop.swift
//  Pixor
//
//  Created by Codex on 2025/2/14.
//

import AppKit
import SwiftUI

@MainActor
extension ContentView {
  /// 处理裁剪结果并引导用户保存裁剪后的图片
  func handleCropRectPrepared(_ rect: CGRect) {
    guard let srcURL = selectedImageURL else { return }
    let panel = NSSavePanel()
    panel.canCreateDirectories = true
    panel.isExtensionHidden = false
    panel.title = L10n.string("crop_save_panel_title")
    let ext = srcURL.pathExtension
    let base = srcURL.deletingPathExtension().lastPathComponent
    panel.nameFieldStringValue = base + "_cropped." + ext
    let res = panel.runModal()
    if res == .OK, let destURL = panel.url {
      do {
        let img = try ImageCropper.crop(url: srcURL, cropRect: rect)
        try ImageCropper.save(image: img, to: destURL)
        withAnimation(Motion.Anim.standard) {
          isCropping = false
          cropAspect = .freeform
        }
      } catch {
        NSSound.beep()
      }
    }
  }
}
