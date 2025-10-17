//
//  PicserAppDelegate.swift
//
//  Created by Eric Cai on 2025/10/09.
//

import AppKit

@MainActor
final class PicserAppDelegate: NSObject, NSApplicationDelegate {
  var externalOpenCoordinator: ExternalOpenCoordinator?

  func configure(externalOpenCoordinator: ExternalOpenCoordinator) {
    self.externalOpenCoordinator = externalOpenCoordinator
  }

  func application(_ application: NSApplication, open urls: [URL]) {
    externalOpenCoordinator?.handleIncoming(urls: urls)
  }

  func application(_ sender: NSApplication, openFile filename: String) -> Bool {
    guard let coordinator = externalOpenCoordinator else { return false }
    let url = URL(fileURLWithPath: filename)
    coordinator.handleIncoming(urls: [url])
    return true
  }
}
