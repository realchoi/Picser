//
//  TagManagementRow.swift
//  Picser
//
//  Created by Eric Cai on 2025/11/11.
//

import SwiftUI

struct TagManagementRow: View {
  let tag: TagRecord
  let isBatchMode: Bool
  let selectionBinding: Binding<Bool>?
  let usageText: String
  let colorBinding: Binding<Color>
  let canClearColor: Bool
  let onClearColor: () -> Void
  let onRename: () -> Void
  let onDelete: () -> Void

  var body: some View {
    HStack(alignment: .center, spacing: 12) {
      if isBatchMode, let selectionBinding {
        Toggle("", isOn: selectionBinding)
          .toggleStyle(.checkbox)
          .labelsHidden()
      }
      VStack(alignment: .leading, spacing: 4) {
        Text(tag.name)
          .font(.headline)
        Text(usageText)
          .font(.caption)
          .foregroundColor(.secondary)
      }
      Spacer()
      colorControl
      Button(action: onRename) {
        Label(L10n.string("tag_settings_rename_button"), systemImage: "pencil")
          .labelStyle(.iconOnly)
      }
      .buttonStyle(.borderless)
      .help(L10n.string("tag_settings_rename_button"))

      Button(role: .destructive, action: onDelete) {
        Label(L10n.string("tag_settings_delete_button"), systemImage: "trash")
          .labelStyle(.iconOnly)
      }
      .buttonStyle(.borderless)
      .help(L10n.string("tag_settings_delete_button"))
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 8)
  }

  private var colorControl: some View {
    HStack(spacing: 8) {
      ColorPicker(
        L10n.string("tag_settings_color_picker_label"),
        selection: colorBinding,
        supportsOpacity: false
      )
      .labelsHidden()
      .frame(width: 34)
      .help(L10n.string("tag_settings_color_picker_label"))

      if canClearColor {
        Button(action: onClearColor) {
          Image(systemName: "gobackward")
        }
        .buttonStyle(.borderless)
        .padding(.leading, 4)
        .help(L10n.string("tag_settings_color_clear_button"))
      }
    }
  }
}
