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
          toggleExifInfoPanel()
        } label: {
          let isActive = showingExifInfo || isLoadingExif
          let iconColor = isActive ? Color.accentColor : Color.primary
          ZStack {
            Image(systemName: isActive ? "info.circle.fill" : "info.circle")
              .foregroundStyle(iconColor)
              .opacity(isShowingExifLoadingIndicator ? 0 : 1)
            if isShowingExifLoadingIndicator {
              ProgressView()
                .scaleEffect(0.8)
                .frame(width: 16, height: 16)
                .tint(iconColor)
            }
          }
          .frame(width: 24, height: 24)
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
            startCropping()
          }
        } label: {
          let isActive = isCropping
          HStack(spacing: 6) {
            Image(systemName: isActive ? "crop.rotate" : "crop")
          }
          .foregroundStyle(isActive ? Color.accentColor : Color.primary)
        }
        .help(L10n.key("crop_button"))
      }

      ToolbarItem {
        Button {
          toggleSlideshowPlayback()
        } label: {
          let isPlaying = isSlideshowActive
          // 幻灯片播放按钮：根据当前状态切换文案与图标
          Label(
            isPlaying
              ? L10n.string("slideshow_toolbar_pause")
              : L10n.string("slideshow_toolbar_play"),
            systemImage: isPlaying ? "pause.circle.fill" : "play.circle"
          )
          .foregroundStyle(isPlaying ? Color.accentColor : Color.primary)
        }
        .disabled(visibleImageURLs.isEmpty)
        .help(L10n.key("slideshow_toolbar_help"))
      }

      ToolbarItem {
        Button {
          withAnimation(Motion.Anim.standard) {
            showingTagEditorPanel.toggle()
          }
        } label: {
          Label(
            showingTagEditorPanel
              ? L10n.string("tag_editor_toolbar_hide")
              : L10n.string("tag_editor_toolbar_show"),
            systemImage: showingTagEditorPanel ? "tag.fill" : "tag"
          )
          .foregroundStyle(showingTagEditorPanel ? Color.accentColor : Color.primary)
        }
        // 允许用户随时展开/收起标签编辑器
        .help(
          showingTagEditorPanel
            ? L10n.string("tag_editor_toolbar_hide")
            : L10n.string("tag_editor_toolbar_show")
        )
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
