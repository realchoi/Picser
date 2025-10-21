//
//  FullDiskAccessChecker.swift
//

import AppKit
import Foundation

enum FullDiskAccessChecker {
  /// 通过尝试读取 TCC 数据库的方式探测是否具有完整磁盘访问权限。
  /// 若无权限，访问会被系统拒绝，抛出无权限错误。
  static func hasFullDiskAccess() -> Bool {
    let probeURL = URL(fileURLWithPath: "/Library/Application Support/com.apple.TCC/TCC.db")
    do {
      let handle = try FileHandle(forReadingFrom: probeURL)
      try handle.close()
      return true
    } catch {
      return false
    }
  }

  /// 尝试直接打开“完整磁盘访问”设置页面，便于用户授权。
  static func openSettings() {
    let candidates = [
      "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles",
      "x-apple.systempreferences:com.apple.preference.security?Privacy_FullDiskAccess",
      "x-apple.systempreferences:com.apple.preference.security"
    ]

    for candidate in candidates {
      if let url = URL(string: candidate), NSWorkspace.shared.open(url) {
        return
      }
    }

    DispatchQueue.main.async {
      if let window = NSApp.keyWindow {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = L10n.string("delete_permission_title")
        alert.informativeText = L10n.string("delete_permission_open_fallback")
        alert.addButton(withTitle: L10n.string("ok_button"))
        alert.beginSheetModal(for: window)
      }
    }
  }
}
