//
//  AppCommands.swift
//  Pixor
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
      Button("open_file_or_folder_button".localized) {
        windowCommands?.openFileOrFolder()
      }
      .keyboardShortcut("o", modifiers: [.command])
      .disabled(windowCommands == nil)

      Button("refresh_button".localized) {
        windowCommands?.refresh()
      }
      .keyboardShortcut("r", modifiers: [.command])
      .disabled(windowCommands == nil)

      // File > Open Recent …
      Menu("open_recent_menu".localized) {
        if recent.items.isEmpty {
          Button("no_recent_items".localized) {}
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
          Button("clear_recent_menu".localized) {
            recent.clear()
          }
        }
      }
    }

    // Note: System provides the standard Settings… (⌘,) via Settings scene

    CommandMenu("image_menu".localized) {
      Button {
        windowCommands?.rotateCCW()
      } label: {
        Label("rotate_ccw_button".localized, systemImage: "rotate.left")
      }
      .keyboardShortcut(appSettings.rotateCCWBaseKey.keyEquivalent, modifiers: modifiers(for: appSettings.rotateCCWModifierKey))
      .disabled(windowCommands == nil)

      Button {
        windowCommands?.rotateCW()
      } label: {
        Label("rotate_cw_button".localized, systemImage: "rotate.right")
      }
      .keyboardShortcut(appSettings.rotateCWBaseKey.keyEquivalent, modifiers: modifiers(for: appSettings.rotateCWModifierKey))
      .disabled(windowCommands == nil)

      Divider()

      Button {
        windowCommands?.mirrorHorizontal()
      } label: {
        Label("mirror_horizontal_button".localized, systemImage: "arrow.left.and.right")
      }
      .keyboardShortcut(appSettings.mirrorHBaseKey.keyEquivalent, modifiers: modifiers(for: appSettings.mirrorHModifierKey))
      .disabled(windowCommands == nil)

      Button {
        windowCommands?.mirrorVertical()
      } label: {
        Label("mirror_vertical_button".localized, systemImage: "arrow.up.and.down")
      }
      .keyboardShortcut(appSettings.mirrorVBaseKey.keyEquivalent, modifiers: modifiers(for: appSettings.mirrorVModifierKey))
      .disabled(windowCommands == nil)

      Divider()

      Button {
        windowCommands?.resetTransform()
      } label: {
        Label("reset_transform_button".localized, systemImage: "arrow.uturn.backward")
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
