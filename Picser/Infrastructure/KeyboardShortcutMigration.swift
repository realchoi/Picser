//
//  KeyboardShortcutMigration.swift
//
//  负责从旧版 UserDefaults 配置迁移到 KeyboardShortcuts 库的存储。
//  当前文件仅提供迁移骨架，后续步骤将补全实际数据同步逻辑。
//

import Foundation
import KeyboardShortcuts

/// 快捷键迁移执行器：用于将历史配置一次性迁移到第三方库管理。
enum KeyboardShortcutMigration {
  /// 标记位 key，迁移完成后写入以避免重复执行。
  private static let migrationFlagKey = "KeyboardShortcutsMigrationCompleted"

  /// 根据需要执行迁移操作。
  /// - Parameters:
  ///   - userDefaults: 持久化存储，默认使用 `.standard`。
  ///   - catalog: 快捷键定义数据源，默认使用单例。
  static func performIfNeeded(
    userDefaults: UserDefaults = .standard,
    catalog: KeyboardShortcutCatalog = .shared
  ) {
    // 占位逻辑：后续步骤将填充迁移实现。
    // 在骨架阶段先行保留对参数的引用，防止编译器发出未使用警告，并为后续代码提供注释引导。
    _ = catalog
    guard !userDefaults.bool(forKey: migrationFlagKey) else { return }

    // TODO: 在后续步骤中读取旧版设置、刷新 KeyboardShortcuts 值并写入迁移完成标记。
  }
}
