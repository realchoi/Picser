//
//  ContentView+Toolbar.swift
//  Pixor
//
//  Created by Codex on 2025/2/14.
//

import SwiftUI

@MainActor
extension ContentView {
  /// 主窗口工具栏内容
  @ToolbarContentBuilder
  var toolbarContent: some ToolbarContent {
    ToolbarItem {
      Button {
        openFileOrFolder()
      } label: {
        Label(
          "open_file_or_folder_button".localized,
          systemImage: "folder")
      }
      .help("open_file_or_folder_button".localized)
    }

    ToolbarItem {
      Button {
        refreshCurrentInputs()
      } label: {
        Label("refresh_button".localized, systemImage: "arrow.clockwise")
      }
      .disabled(currentSourceInputs.isEmpty)
      .help("refresh_button".localized)
    }

    if selectedImageURL != nil {
      ToolbarItem {
        Button {
          featureGatekeeper.perform(.exif, context: .generic, requestUpgrade: requestUpgrade) {
            showExifInfo()
          }
        } label: {
          HStack(spacing: 4) {
            if isLoadingExif {
              ProgressView()
                .scaleEffect(0.8)
                .frame(width: 16, height: 16)
            } else {
              Image(systemName: "info.circle")
            }

            if isLoadingExif {
              Text("loading_text".localized)
                .font(.caption)
            }
          }
        }
        .disabled(isLoadingExif)
        .help(
          isLoadingExif
            ? "exif_loading_hint".localized
            : "exif_info_button".localized)
      }

      ToolbarItem {
        Button {
          rotateCCW()
        } label: {
          Label("rotate_ccw_button".localized, systemImage: "rotate.left")
        }
        .help("rotate_ccw_button".localized)
      }

      ToolbarItem {
        Button {
          rotateCW()
        } label: {
          Label("rotate_cw_button".localized, systemImage: "rotate.right")
        }
        .help("rotate_cw_button".localized)
      }

      ToolbarItem {
        Button {
          mirrorHorizontal()
        } label: {
          Label("mirror_horizontal_button".localized, systemImage: "arrow.left.and.right")
        }
        .help("mirror_horizontal_button".localized)
      }

      ToolbarItem {
        Button {
          mirrorVertical()
        } label: {
          Label("mirror_vertical_button".localized, systemImage: "arrow.up.and.down")
        }
        .help("mirror_vertical_button".localized)
      }

      ToolbarItem {
        Button {
          performIfEntitled(.crop) {
            withAnimation(Motion.Anim.standard) {
              isCropping.toggle()
              if !isCropping {
                cropAspect = .freeform
              }
            }
          }
        } label: {
          Label("crop_button".localized, systemImage: isCropping ? "crop.rotate" : "crop")
        }
        .help("crop_button".localized)
      }
    }
  }
}
