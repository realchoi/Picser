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
  private var didConfigurePragmas = false
  private var didRunMigrations = false

  init(databaseURL: URL? = nil) {
    let fm = FileManager.default
    if let databaseURL {
      self.databaseURL = databaseURL
    } else {
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
    try await runMigrationsIfNeeded()
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
    try configureDatabaseIfNeeded()
  }

  private func runMigrationsIfNeeded() async throws {
    guard !didRunMigrations else { return }
    try await migrateIfNeeded()
    didRunMigrations = true
  }

  private func migrateIfNeeded() async throws {
    try await ensureConnection()
    guard let handle else {
      throw TaggingDatabaseError.uninitialized
    }
    let currentVersion = try await userVersion()
    let ordered = TaggingDatabase.migrations.sorted { $0.version < $1.version }
    for migration in ordered where migration.version > currentVersion {
      try migration.apply(handle)
      try setUserVersion(migration.version, db: handle)
    }
  }

  // MARK: - Helpers

  private func execute(_ sql: String, db: OpaquePointer) throws {
    var errorMessage: UnsafeMutablePointer<Int8>?
    let result = sqlite3_exec(db, sql, nil, nil, &errorMessage)
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

  private func setUserVersion(_ value: Int, db: OpaquePointer) throws {
    try execute("PRAGMA user_version = \(value);", db: db)
  }

  private func lastErrorMessage(from handle: OpaquePointer? = nil) -> String {
    let pointer = handle ?? self.handle
    if let pointer, let cString = sqlite3_errmsg(pointer) {
      return String(cString: cString)
    }
    return "unknown"
  }

  private func configureDatabaseIfNeeded() throws {
    guard let handle else { throw TaggingDatabaseError.uninitialized }
    guard !didConfigurePragmas else { return }
    try execute("PRAGMA foreign_keys = ON;", db: handle)
    try execute("PRAGMA journal_mode = WAL;", db: handle)
    try execute("PRAGMA synchronous = NORMAL;", db: handle)
    try execute("PRAGMA temp_store = MEMORY;", db: handle)
    try execute("PRAGMA busy_timeout = 5000;", db: handle)
    didConfigurePragmas = true
  }
}

private struct DatabaseMigration {
  let version: Int
  let name: String
  let apply: (OpaquePointer) throws -> Void
}

extension TaggingDatabase {
  private static let migrations: [DatabaseMigration] = [
    DatabaseMigration(version: 1, name: "Initial schema") { db in
      let statements = [
        """
        CREATE TABLE IF NOT EXISTS tags (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL UNIQUE,
          color_hex TEXT,
          created_at REAL NOT NULL,
          updated_at REAL NOT NULL
        );
        """,
        """
        CREATE TABLE IF NOT EXISTS images (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          path TEXT NOT NULL UNIQUE,
          file_name TEXT NOT NULL,
          directory TEXT NOT NULL,
          created_at REAL NOT NULL,
          updated_at REAL NOT NULL
        );
        """,
        """
        CREATE TABLE IF NOT EXISTS image_tags (
          image_id INTEGER NOT NULL REFERENCES images(id) ON DELETE CASCADE,
          tag_id INTEGER NOT NULL REFERENCES tags(id) ON DELETE CASCADE,
          created_at REAL NOT NULL,
          PRIMARY KEY(image_id, tag_id)
        );
        """,
        "CREATE INDEX IF NOT EXISTS idx_tags_name ON tags(name COLLATE NOCASE);",
        "CREATE INDEX IF NOT EXISTS idx_image_tags_tag_id ON image_tags(tag_id);",
        "CREATE INDEX IF NOT EXISTS idx_image_tags_image_id ON image_tags(image_id);"
      ]
      try runStatements(statements, on: db)
    },
    DatabaseMigration(version: 2, name: "Image metadata columns") { db in
      let statements = [
        "ALTER TABLE images ADD COLUMN file_identifier TEXT;",
        "ALTER TABLE images ADD COLUMN bookmark BLOB;",
        "CREATE INDEX IF NOT EXISTS idx_images_file_identifier ON images(file_identifier);"
      ]
      try runStatements(statements, on: db)
    }
  ]

  private static func runStatements(_ statements: [String], on db: OpaquePointer) throws {
    for statement in statements {
      let trimmed = statement.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !trimmed.isEmpty else { continue }
      var errorMessage: UnsafeMutablePointer<Int8>?
      let result = sqlite3_exec(db, trimmed, nil, nil, &errorMessage)
      if result != SQLITE_OK {
        let message = errorMessage.map { String(cString: $0) } ?? "未知错误"
        sqlite3_free(errorMessage)
        throw TaggingDatabaseError.executionFailed(code: result, message: message, sql: trimmed)
      }
    }
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
