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

// MARK: - Notification Keys
extension Notification.Name {
  static let openFileOrFolderRequested = Notification.Name("openFileOrFolderRequested")
  static let openFolderURLRequested = Notification.Name("openFolderURLRequested")
  static let refreshRequested = Notification.Name("refreshRequested")
  static let rotateCCWRequested = Notification.Name("rotateCCWRequested")
  static let rotateCWRequested = Notification.Name("rotateCWRequested")
  static let mirrorHRequested = Notification.Name("mirrorHRequested")
  static let mirrorVRequested = Notification.Name("mirrorVRequested")
  static let resetTransformRequested = Notification.Name("resetTransformRequested")
  // Crop flow
  static let cropCommitRequested = Notification.Name("cropCommitRequested")
  static let cropRectPrepared = Notification.Name("cropRectPrepared")
}

// MARK: - App Commands
struct AppCommands: Commands {
  @ObservedObject var recent: RecentOpensManager
  // Observe language changes to update menu titles without rebuilding the app view tree
  @ObservedObject private var localization = LocalizationManager.shared
  @ObservedObject var appSettings: AppSettings
  var body: some Commands {
    // Add "Open…" under File with ⌘O
    CommandGroup(after: .newItem) {
      Button("open_file_or_folder_button".localized) {
        NotificationCenter.default.post(name: .openFileOrFolderRequested, object: nil)
      }
      .keyboardShortcut("o", modifiers: [.command])

      Button("refresh_button".localized) {
        NotificationCenter.default.post(name: .refreshRequested, object: nil)
      }
      .keyboardShortcut("r", modifiers: [.command])

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
              recent.open(item: item)
            } label: {
              RecentMenuItemView(folderName: folderName, fullPath: folderURL.path)
            }
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
        NotificationCenter.default.post(name: .rotateCCWRequested, object: nil)
      } label: {
        Label("rotate_ccw_button".localized, systemImage: "rotate.left")
      }
      .keyboardShortcut(appSettings.rotateCCWBaseKey.keyEquivalent, modifiers: modifiers(for: appSettings.rotateCCWModifierKey))

      Button {
        NotificationCenter.default.post(name: .rotateCWRequested, object: nil)
      } label: {
        Label("rotate_cw_button".localized, systemImage: "rotate.right")
      }
      .keyboardShortcut(appSettings.rotateCWBaseKey.keyEquivalent, modifiers: modifiers(for: appSettings.rotateCWModifierKey))

      Divider()

      Button {
        NotificationCenter.default.post(name: .mirrorHRequested, object: nil)
      } label: {
        Label("mirror_horizontal_button".localized, systemImage: "arrow.left.and.right")
      }
      .keyboardShortcut(appSettings.mirrorHBaseKey.keyEquivalent, modifiers: modifiers(for: appSettings.mirrorHModifierKey))

      Button {
        NotificationCenter.default.post(name: .mirrorVRequested, object: nil)
      } label: {
        Label("mirror_vertical_button".localized, systemImage: "arrow.up.and.down")
      }
      .keyboardShortcut(appSettings.mirrorVBaseKey.keyEquivalent, modifiers: modifiers(for: appSettings.mirrorVModifierKey))

      Divider()

      Button {
        NotificationCenter.default.post(name: .resetTransformRequested, object: nil)
      } label: {
        Label("reset_transform_button".localized, systemImage: "arrow.uturn.backward")
      }
      .keyboardShortcut(appSettings.resetTransformBaseKey.keyEquivalent, modifiers: modifiers(for: appSettings.resetTransformModifierKey))
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
