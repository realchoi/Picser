//
//  ContentView+Exif.swift
//
//  Created by Eric Cai on 2025/9/19.
//

import SwiftUI

@MainActor
extension ContentView {
  /// 加载并展示当前图片的 EXIF 信息
  func showExifInfo() {
    performIfEntitled(.exif) {
      guard let currentURL = selectedImageURL else {
        alertContent = AlertContent(
          title: L10n.string("exif_loading_error_title"),
          message: L10n.string("exif_no_image_selected")
        )
        return
      }

      currentExifInfo = nil
      startExifLoad(for: currentURL, shouldPresentPanel: true)
    }
  }

  /// 取消当前 EXIF 加载任务并重置状态
  func cancelOngoingExifLoad() {
    exifLoadTask?.cancel()
    exifLoadTask = nil
    exifLoadRequestID = nil
    isLoadingExif = false
  }

  /// 启动 EXIF 信息加载任务
  func startExifLoad(for url: URL, shouldPresentPanel: Bool) {
    exifLoadTask?.cancel()
    exifLoadTask = nil

    let requestID = UUID()
    exifLoadRequestID = requestID
    isLoadingExif = true

    if shouldPresentPanel {
      showingExifInfo = true
    }

    exifLoadTask = Task {
      do {
        let exifInfo = try await ExifExtractor.loadExifInfo(for: url)
        guard !Task.isCancelled else { return }
        await MainActor.run {
          guard self.exifLoadRequestID == requestID else { return }
          guard self.selectedImageURL == url else { return }
          self.currentExifInfo = exifInfo
          self.isLoadingExif = false
          self.exifLoadTask = nil
          self.exifLoadRequestID = nil
        }
      } catch ExifExtractionError.failedToCreateImageSource {
        guard !Task.isCancelled else { return }
        await MainActor.run {
          guard self.exifLoadRequestID == requestID else { return }
          self.isLoadingExif = false
          self.exifLoadTask = nil
          self.exifLoadRequestID = nil
          self.showingExifInfo = false
          self.alertContent = AlertContent(
            title: L10n.string("exif_loading_error_title"),
            message: L10n.string("exif_file_read_error")
          )
        }
      } catch ExifExtractionError.failedToExtractProperties {
        guard !Task.isCancelled else { return }
        await MainActor.run {
          guard self.exifLoadRequestID == requestID else { return }
          self.isLoadingExif = false
          self.exifLoadTask = nil
          self.exifLoadRequestID = nil
          self.showingExifInfo = false
          self.alertContent = AlertContent(
            title: L10n.string("exif_loading_error_title"),
            message: L10n.string("exif_metadata_extract_error")
          )
        }
      } catch {
        guard !Task.isCancelled else { return }
        await MainActor.run {
          guard self.exifLoadRequestID == requestID else { return }
          self.isLoadingExif = false
          self.exifLoadTask = nil
          self.exifLoadRequestID = nil
          self.showingExifInfo = false
          self.alertContent = AlertContent(
            title: L10n.string("exif_loading_error_title"),
            message: L10n.string("exif_unexpected_error")
          )
        }
      }
    }
  }
}
