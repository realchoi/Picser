//
//  TaggingDatabase.swift
//
//  Created by Eric Cai on 2025/11/08.
//

import Foundation
import SQLite3

/// SQLite 标签数据库，负责连接管理与迁移
actor TaggingDatabase {
  static let shared = TaggingDatabase()

  private let databaseURL: URL
  private var handle: OpaquePointer?

  private init() {
    let fm = FileManager.default
    let appSupport = try? fm.url(
      for: .applicationSupportDirectory,
      in: .userDomainMask,
      appropriateFor: nil,
      create: true
    )
    let bundleID = Bundle.main.bundleIdentifier ?? "com.picser.app"
    let folder = (appSupport ?? fm.temporaryDirectory).appendingPathComponent(bundleID, isDirectory: true)
    if !fm.fileExists(atPath: folder.path) {
      try? fm.createDirectory(at: folder, withIntermediateDirectories: true)
    }
    self.databaseURL = folder.appendingPathComponent("tags.sqlite3")

    // 初始化后立即异步打开数据库并执行迁移，避免首次调用卡顿
    Task {
      do {
        try await openIfNeeded()
        try await migrateIfNeeded()
      } catch {
        assertionFailure("无法初始化标签数据库: \(error)")
      }
    }
  }

  deinit {
    if let handle {
      sqlite3_close(handle)
    }
  }

  // MARK: - Public API

  func perform<T>(_ block: (OpaquePointer) throws -> T) async throws -> T {
    try await ensureConnection()
    guard let handle else {
      throw TaggingDatabaseError.uninitialized
    }
    // 对外暴露串行化入口，调用方无需关心锁
    return try block(handle)
  }

  // MARK: - Connection & Migration

  private func ensureConnection() async throws {
    if handle == nil {
      try await openIfNeeded()
    }
  }

  private func openIfNeeded() async throws {
    if handle != nil { return }
    var db: OpaquePointer?
    let flags = SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
    let result = sqlite3_open_v2(databaseURL.path, &db, flags, nil)
    guard result == SQLITE_OK, let db else {
      throw TaggingDatabaseError.openFailed(code: result, message: lastErrorMessage(from: db))
    }
    handle = db
    try await execute("PRAGMA foreign_keys = ON;")
  }

  private func migrateIfNeeded() async throws {
    let currentVersion = try await userVersion()
    if currentVersion < 1 {
      // V1: 基础标签/图片/关联表
      try await performMigrationV1()
      try await setUserVersion(1)
    }
    if currentVersion < 2 {
      // V2: 增加文件唯一标识与书签，支持断开连接恢复
      try await performMigrationV2()
      try await setUserVersion(2)
    }
  }

  private func performMigrationV1() async throws {
    let migrationSQL = """
      CREATE TABLE IF NOT EXISTS tags (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL UNIQUE,
        color_hex TEXT,
        created_at REAL NOT NULL,
        updated_at REAL NOT NULL
      );
      CREATE TABLE IF NOT EXISTS images (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        path TEXT NOT NULL UNIQUE,
        file_name TEXT NOT NULL,
        directory TEXT NOT NULL,
        created_at REAL NOT NULL,
        updated_at REAL NOT NULL
      );
      CREATE TABLE IF NOT EXISTS image_tags (
        image_id INTEGER NOT NULL REFERENCES images(id) ON DELETE CASCADE,
        tag_id INTEGER NOT NULL REFERENCES tags(id) ON DELETE CASCADE,
        created_at REAL NOT NULL,
        PRIMARY KEY(image_id, tag_id)
      );
      CREATE INDEX IF NOT EXISTS idx_tags_name ON tags(name COLLATE NOCASE);
      CREATE INDEX IF NOT EXISTS idx_image_tags_tag_id ON image_tags(tag_id);
      CREATE INDEX IF NOT EXISTS idx_image_tags_image_id ON image_tags(image_id);
    """
    // 将多条建表语句拆成独立执行，便于排查失败语句
    let statements = migrationSQL.split(separator: ";")
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
    for statement in statements {
      try await execute("\(statement);")
    }
  }

  private func performMigrationV2() async throws {
    let statements = [
      "ALTER TABLE images ADD COLUMN file_identifier TEXT",
      "ALTER TABLE images ADD COLUMN bookmark BLOB",
      "CREATE INDEX IF NOT EXISTS idx_images_file_identifier ON images(file_identifier)"
    ]
    for sql in statements {
      try await execute("\(sql);")
    }
  }

  // MARK: - Helpers

  private func execute(_ sql: String) async throws {
    try await ensureConnection()
    guard let handle else { throw TaggingDatabaseError.uninitialized }
    // 简单语句直接用 sqlite3_exec，避免重复准备 statement
    var errorMessage: UnsafeMutablePointer<Int8>?
    let result = sqlite3_exec(handle, sql, nil, nil, &errorMessage)
    if result != SQLITE_OK {
      let message = errorMessage.map { String(cString: $0) } ?? "未知错误"
      sqlite3_free(errorMessage)
      throw TaggingDatabaseError.executionFailed(code: result, message: message, sql: sql)
    }
  }

  private func userVersion() async throws -> Int {
    var statement: OpaquePointer?
    defer { sqlite3_finalize(statement) }
    try await ensureConnection()
    guard let handle else { throw TaggingDatabaseError.uninitialized }
    if sqlite3_prepare_v2(handle, "PRAGMA user_version;", -1, &statement, nil) != SQLITE_OK {
      throw TaggingDatabaseError.prepareFailed(message: lastErrorMessage())
    }
    if sqlite3_step(statement) == SQLITE_ROW {
      return Int(sqlite3_column_int(statement, 0))
    }
    return 0
  }

  private func setUserVersion(_ value: Int) async throws {
    try await execute("PRAGMA user_version = \(value);")
  }

  private func lastErrorMessage(from handle: OpaquePointer? = nil) -> String {
    let pointer = handle ?? self.handle
    if let pointer, let cString = sqlite3_errmsg(pointer) {
      return String(cString: cString)
    }
    return "unknown"
  }
}

enum TaggingDatabaseError: LocalizedError {
  case uninitialized
  case openFailed(code: Int32, message: String)
  case executionFailed(code: Int32, message: String, sql: String)
  case prepareFailed(message: String)

  var errorDescription: String? {
    switch self {
    case .uninitialized:
      return "数据库尚未初始化"
    case let .openFailed(code, message):
      return "打开数据库失败 (\(code))：\(message)"
    case let .executionFailed(code, message, sql):
      return "执行 SQL 失败 (\(code))：\(message)\nSQL: \(sql)"
    case let .prepareFailed(message):
      return "预编译 SQL 失败：\(message)"
    }
  }
}
