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
}

// MARK: - App Commands
struct AppCommands: Commands {
  var body: some Commands {
    // Add "Open…" under File with ⌘O
    CommandGroup(after: .newItem) {
      Button("open_file_or_folder_button".localized) {
        NotificationCenter.default.post(name: .openFileOrFolderRequested, object: nil)
      }
      .keyboardShortcut("o", modifiers: [.command])
    }

    // Note: System provides the standard Settings… (⌘,) via Settings scene
  }
}
