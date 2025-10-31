//
//  AppCommands.swift
//
//  Created by Eric Cai on 2025/9/9.
//
//  Adds macOS-friendly menu items and shortcuts.
//

import SwiftUI
import AppKit

// MARK: - Notification Keys (crop flow remains notification-based)
extension Notification.Name {
  static let cropCommitRequested = Notification.Name("cropCommitRequested")
  static let cropRectPrepared = Notification.Name("cropRectPrepared")
}

// MARK: - App Commands
struct AppCommands: Commands {
  @ObservedObject var recent: RecentOpensManager
  // Observe language changes to update menu titles without rebuilding the app view tree
  @ObservedObject private var localization = LocalizationManager.shared
  @ObservedObject var appSettings: AppSettings
  @FocusedValue(\.windowCommandHandlers) private var windowCommands
  var body: some Commands {
    // Add "Open…" under File with ⌘O
    CommandGroup(after: .newItem) {
      Button(L10n.string("open_file_or_folder_button")) {
        windowCommands?.openFileOrFolder()
      }
      .keyboardShortcut("o", modifiers: [.command])
      .disabled(windowCommands == nil)

      Button(L10n.string("refresh_button")) {
        windowCommands?.refresh()
      }
      .keyboardShortcut("r", modifiers: [.command])
      .disabled(windowCommands == nil)

      // File > Open Recent …
      Menu(L10n.string("open_recent_menu")) {
        if recent.items.isEmpty {
          Button(L10n.string("no_recent_items")) {}
            .disabled(true)
        } else {
          ForEach(recent.items) { item in
            let folderURL = URL(fileURLWithPath: item.path)
            let folderName = folderURL.lastPathComponent
            Button {
              if let url = recent.open(item: item) {
                windowCommands?.openResolvedURL(url)
              }
            } label: {
              RecentMenuItemView(folderName: folderName, fullPath: folderURL.path)
            }
            .disabled(windowCommands == nil)
          }
          Divider()
          Button(L10n.string("clear_recent_menu")) {
            recent.clear()
          }
        }
      }
    }

    // Note: System provides the standard Settings… (⌘,) via Settings scene

    CommandMenu(L10n.string("image_menu")) {
      commandMenuButton(
        title: L10n.string("rotate_ccw_button"),
        systemImage: "rotate.left",
        shortcut: appSettings.formattedShortcutDescription(for: .rotateCounterclockwise)
      ) {
        windowCommands?.rotateCCW()
      }
      .disabled(windowCommands == nil)

      commandMenuButton(
        title: L10n.string("rotate_cw_button"),
        systemImage: "rotate.right",
        shortcut: appSettings.formattedShortcutDescription(for: .rotateClockwise)
      ) {
        windowCommands?.rotateCW()
      }
      .disabled(windowCommands == nil)

      Divider()

      commandMenuButton(
        title: L10n.string("mirror_horizontal_button"),
        systemImage: "arrow.left.and.right",
        shortcut: appSettings.formattedShortcutDescription(for: .mirrorHorizontal)
      ) {
        windowCommands?.mirrorHorizontal()
      }
      .disabled(windowCommands == nil)

      commandMenuButton(
        title: L10n.string("mirror_vertical_button"),
        systemImage: "arrow.up.and.down",
        shortcut: appSettings.formattedShortcutDescription(for: .mirrorVertical)
      ) {
        windowCommands?.mirrorVertical()
      }
      .disabled(windowCommands == nil)

      Divider()

      commandMenuButton(
        title: L10n.string("reset_transform_button"),
        systemImage: "arrow.uturn.backward",
        shortcut: appSettings.formattedShortcutDescription(for: .resetTransform)
      ) {
        windowCommands?.resetTransform()
      }
      .disabled(windowCommands == nil)
    }

  }

  /// 构建带有快捷键信息的菜单按钮。
  private func commandMenuButton(
    title: String,
    systemImage: String,
    shortcut: String?,
    action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      HStack {
        Label(title, systemImage: systemImage)
        if let shortcut {
          Spacer(minLength: 12)
          Text(shortcut)
            .font(.caption)
            .foregroundColor(.secondary)
        }
      }
    }
  }
}
