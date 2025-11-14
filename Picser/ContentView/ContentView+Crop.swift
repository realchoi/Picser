//
//  ContentView+Crop.swift
//
//  Created by Eric Cai on 2025/9/19.
//

import AppKit
import SwiftUI

@MainActor
extension ContentView {
  /// 开始裁剪操作（在点击裁剪按钮时调用）
  func startCropping() {
    guard let url = selectedImageURL else { return }

    // 检查格式是否支持裁剪
    if !FormatUtils.supports(.supportsCropping, url: url) {
      // 格式不支持裁剪，立即提示用户
      let format = FormatUtils.fileFormat(from: url.lastPathComponent)
      let message = String(
        format: L10n.string("crop_save_unsupported_format"),
        format
      )
      alertContent = AlertContent(
        title: L10n.string("crop_save_error_title"),
        message: message
      )
      return
    }

    // 格式支持裁剪，进入裁剪模式
    withAnimation(Motion.Anim.standard) {
      isCropping.toggle()
      if !isCropping {
        cropAspect = .freeform
      }
    }
  }

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
      } catch ImageCropperError.unsupportedFormat {
        // 矢量格式（如 SVG）不支持裁剪操作
        let format = FormatUtils.fileFormat(from: srcURL.lastPathComponent)
        let message = String(
          format: L10n.string("crop_save_unsupported_format"),
          format
        )
        alertContent = AlertContent(
          title: L10n.string("crop_save_error_title"),
          message: message
        )
      } catch {
        // 其他裁剪或保存错误
        NSSound.beep()
        alertContent = AlertContent(
          title: L10n.string("crop_save_error_title"),
          message: L10n.string("crop_save_error_message")
        )
      }
    }
  }
}
