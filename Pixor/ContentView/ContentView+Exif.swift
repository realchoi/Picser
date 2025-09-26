//
//  ContentView+Exif.swift
//  Pixor
//
//  Created by Codex on 2025/2/14.
//

import SwiftUI

@MainActor
extension ContentView {
  /// 加载并展示当前图片的 EXIF 信息
  func showExifInfo() {
    performIfEntitled(.exif) {
      guard let currentURL = selectedImageURL else {
        alertContent = AlertContent(
          title: "exif_loading_error_title".localized,
          message: "exif_no_image_selected".localized
        )
        return
      }

      guard !isLoadingExif else { return }
      isLoadingExif = true

      Task {
        do {
          let exifInfo = try await ExifExtractor.loadExifInfo(for: currentURL)
          await MainActor.run {
            self.isLoadingExif = false
            self.currentExifInfo = exifInfo
            self.showingExifInfo = true
          }
        } catch ExifExtractionError.failedToCreateImageSource {
          await MainActor.run {
            self.isLoadingExif = false
            self.alertContent = AlertContent(
              title: "exif_loading_error_title".localized,
              message: "exif_file_read_error".localized
            )
          }
        } catch ExifExtractionError.failedToExtractProperties {
          await MainActor.run {
            self.isLoadingExif = false
            self.alertContent = AlertContent(
              title: "exif_loading_error_title".localized,
              message: "exif_metadata_extract_error".localized
            )
          }
        } catch {
          await MainActor.run {
            self.isLoadingExif = false
            self.alertContent = AlertContent(
              title: "exif_loading_error_title".localized,
              message: "exif_unexpected_error".localized
            )
          }
        }
      }
    }
  }
}
