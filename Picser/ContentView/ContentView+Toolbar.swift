//
//  ContentView+Toolbar.swift
//
//  Created by Eric Cai on 2025/9/19.
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
          L10n.string("open_file_or_folder_button"),
          systemImage: "folder")
      }
      .help(L10n.key("open_file_or_folder_button"))
    }

    ToolbarItem {
      Button {
        refreshCurrentInputs()
      } label: {
        Label(L10n.key("refresh_button"), systemImage: "arrow.clockwise")
      }
      .disabled(currentSourceInputs.isEmpty)
      .help(L10n.key("refresh_button"))
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
              Text(l10n: "loading_text")
                .font(.caption)
            }
          }
        }
        .disabled(isLoadingExif)
        .help(
          isLoadingExif
            ? L10n.string("exif_loading_hint")
            : L10n.string("exif_info_button"))
      }

      ToolbarItem {
        Button {
          rotateCCW()
        } label: {
          Label(L10n.key("rotate_ccw_button"), systemImage: "rotate.left")
        }
        .help(L10n.key("rotate_ccw_button"))
      }

      ToolbarItem {
        Button {
          rotateCW()
        } label: {
          Label(L10n.key("rotate_cw_button"), systemImage: "rotate.right")
        }
        .help(L10n.key("rotate_cw_button"))
      }

      ToolbarItem {
        Button {
          mirrorHorizontal()
        } label: {
          Label(L10n.key("mirror_horizontal_button"), systemImage: "arrow.left.and.right")
        }
        .help(L10n.key("mirror_horizontal_button"))
      }

      ToolbarItem {
        Button {
          mirrorVertical()
        } label: {
          Label(L10n.key("mirror_vertical_button"), systemImage: "arrow.up.and.down")
        }
        .help(L10n.key("mirror_vertical_button"))
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
          Label(L10n.key("crop_button"), systemImage: isCropping ? "crop.rotate" : "crop")
        }
        .help(L10n.key("crop_button"))
      }

      ToolbarItem {
        Button {
          requestDeletion()
        } label: {
          Label(L10n.key("delete_button"), systemImage: "trash")
        }
        // 删除执行期间禁用按钮，避免重复触发
        .disabled(isPerformingDeletion)
        .help(L10n.key("delete_button"))
      }
    }
  }
}
