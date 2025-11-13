//
//  TagBatchControlsView.swift
//  Picser
//
//  Created by Eric Cai on 2025/11/11.
//

import SwiftUI

/// 承载标签批量操作的控制区域
struct TagBatchControlsView: View {
  @ObservedObject var store: TagSettingsStore
  let onShowBatchAddSheet: () -> Void
  let showsHeader: Bool

  init(
    store: TagSettingsStore,
    onShowBatchAddSheet: @escaping () -> Void,
    showsHeader: Bool = true
  ) {
    _store = ObservedObject(wrappedValue: store)
    self.onShowBatchAddSheet = onShowBatchAddSheet
    self.showsHeader = showsHeader
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      if showsHeader {
        headerRow
      }
      if store.isBatchModeEnabled {
        batchToolbox
      }
    }
  }

  private var headerRow: some View {
    HStack {
      Toggle(isOn: $store.isBatchModeEnabled) {
        Label(L10n.string("tag_settings_batch_mode_toggle"), systemImage: "square.stack.3d.up")
      }
      .toggleStyle(.switch)

      Spacer()

      Button(action: onShowBatchAddSheet) {
        Label(L10n.string("tag_settings_batch_add_button"), systemImage: "plus.circle")
      }
    }
  }

  private var batchToolbox: some View {
    VStack(alignment: .leading, spacing: 8) {
      colorToolbar
      actionToolbar
    }
  }

  private var colorToolbar: some View {
    HStack(spacing: 12) {
      Text(
        String(
          format: L10n.string("tag_settings_batch_selection_count"),
          store.selectedTagIDs.count
        )
      )
      .font(.caption)
      .foregroundColor(.secondary)

      ColorPicker(
        L10n.string("tag_settings_batch_color_picker"),
        selection: $store.batchColor,
        supportsOpacity: false
      )
      .labelsHidden()

      Button {
        store.applyBatchColor()
      } label: {
        Label(L10n.string("tag_settings_batch_apply_color"), systemImage: "paintpalette")
      }
      .buttonStyle(.borderedProminent)
      .disabled(store.selectedTagIDs.isEmpty)

      Button {
        store.clearBatchColor()
      } label: {
        Label(L10n.string("tag_settings_batch_clear_color"), systemImage: "eraser")
      }
      .buttonStyle(.bordered)
      .disabled(store.selectedTagIDs.isEmpty)

      Spacer()
    }
  }

  private var actionToolbar: some View {
    HStack(spacing: 12) {
      Button {
        store.isShowingClearAssignmentsConfirm = true
      } label: {
        Label(L10n.string("tag_settings_clear_assignments_button"), systemImage: "minus.circle")
      }
      .disabled(store.selectedTagIDs.isEmpty)

      Button {
        store.mergeTargetName = ""
        store.isShowingMergeSheet = true
      } label: {
        Label(L10n.string("tag_settings_merge_button"), systemImage: "arrow.triangle.merge")
      }
      .disabled(store.selectedTagIDs.count < 2)

      Spacer()

      Button(role: .destructive) {
        store.isShowingDeleteConfirm = true
      } label: {
        Label(L10n.string("tag_settings_batch_delete_button"), systemImage: "trash")
      }
      .disabled(store.selectedTagIDs.isEmpty)
    }
  }
}
