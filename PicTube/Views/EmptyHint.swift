//
//  EmptyHint.swift
//  PicTube
//
//  Extracted from ContentView to keep it lean.
//

import SwiftUI

/// 空状态提示视图，显示打开文件/文件夹按钮和拖拽提示。
struct EmptyHint: View {
  let onOpen: () -> Void

  var body: some View {
    VStack(spacing: 16) {
      Button {
        onOpen()
      } label: {
        Label(
          "open_file_or_folder_button".localized,
          systemImage: "folder"
        )
        .padding(8)
      }
      .buttonStyle(.borderedProminent)
      .controlSize(.extraLarge)
      .font(.title2)
      .labelStyle(.titleAndIcon)

      // 额外提示：支持拖拽文件/文件夹打开
      HStack(spacing: 8) {
        Image(systemName: "tray.and.arrow.down")
          .foregroundStyle(.secondary)
        Text("empty_drag_hint".localized)
          .foregroundStyle(.secondary)
      }
      .font(.body)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}

