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
      Button {
        windowCommands?.rotateCCW()
      } label: {
        Label(L10n.string("rotate_ccw_button"), systemImage: "rotate.left")
      }
      .keyboardShortcut(appSettings.rotateCCWBaseKey.keyEquivalent, modifiers: modifiers(for: appSettings.rotateCCWModifierKey))
      .disabled(windowCommands == nil)

      Button {
        windowCommands?.rotateCW()
      } label: {
        Label(L10n.string("rotate_cw_button"), systemImage: "rotate.right")
      }
      .keyboardShortcut(appSettings.rotateCWBaseKey.keyEquivalent, modifiers: modifiers(for: appSettings.rotateCWModifierKey))
      .disabled(windowCommands == nil)

      Divider()

      Button {
        windowCommands?.mirrorHorizontal()
      } label: {
        Label(L10n.string("mirror_horizontal_button"), systemImage: "arrow.left.and.right")
      }
      .keyboardShortcut(appSettings.mirrorHBaseKey.keyEquivalent, modifiers: modifiers(for: appSettings.mirrorHModifierKey))
      .disabled(windowCommands == nil)

      Button {
        windowCommands?.mirrorVertical()
      } label: {
        Label(L10n.string("mirror_vertical_button"), systemImage: "arrow.up.and.down")
      }
      .keyboardShortcut(appSettings.mirrorVBaseKey.keyEquivalent, modifiers: modifiers(for: appSettings.mirrorVModifierKey))
      .disabled(windowCommands == nil)

      Divider()

      Button {
        windowCommands?.resetTransform()
      } label: {
        Label(L10n.string("reset_transform_button"), systemImage: "arrow.uturn.backward")
      }
      .keyboardShortcut(appSettings.resetTransformBaseKey.keyEquivalent, modifiers: modifiers(for: appSettings.resetTransformModifierKey))
      .disabled(windowCommands == nil)
    }

  }

  // Convert our ModifierKey to SwiftUI EventModifiers
  private func modifiers(for key: ModifierKey) -> EventModifiers {
    switch key {
    case .none: return []
    case .command: return [.command]
    case .option: return [.option]
    case .control: return [.control]
    case .shift: return [.shift]
    }
  }
}
