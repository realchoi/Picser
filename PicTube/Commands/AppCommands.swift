//
//  AppCommands.swift
//  PicTube
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
}

// MARK: - App Commands
struct AppCommands: Commands {
  @ObservedObject var recent: RecentOpensManager
  var body: some Commands {
    // Add "Open…" under File with ⌘O
    CommandGroup(after: .newItem) {
      Button("open_file_or_folder_button".localized) {
        NotificationCenter.default.post(name: .openFileOrFolderRequested, object: nil)
      }
      .keyboardShortcut("o", modifiers: [.command])

      // File > Open Recent …
      Menu("open_recent_menu".localized) {
        if recent.items.isEmpty {
          Button("no_recent_items".localized) {}
            .disabled(true)
        } else {
          ForEach(recent.items) { item in
            let folderName = URL(fileURLWithPath: item.path).lastPathComponent
            Button(folderName) {
              recent.open(item: item)
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
  }
}
