//
//  TaggingDatabase.swift
//
//  Created by Eric Cai on 2025/11/08.
//

import Foundation
import SQLite3

/// SQLite 标签数据库管理器
///
/// 职责：
/// 1. **连接管理**：建立和维护 SQLite 数据库连接
/// 2. **迁移管理**：自动执行数据库版本迁移
/// 3. **并发控制**：使用 actor 确保所有数据库操作串行执行
/// 4. **配置管理**：设置 WAL 模式、外键约束等数据库参数
///
/// 线程安全：
/// - 使用 actor 隔离，所有操作自动串行化
/// - SQLite 以 FULLMUTEX 模式打开，允许多线程安全访问
/// - perform() 方法是唯一的公开入口，确保所有操作都经过 actor 调度
///
/// 数据库位置：
/// - 生产环境：~/Library/Application Support/[BundleID]/tags.sqlite3
/// - 测试环境：可自定义路径（通过构造函数传入）
actor TaggingDatabase {
  /// 全局单例
  static let shared = TaggingDatabase()

  /// 数据库文件 URL
  private let databaseURL: URL

  /// SQLite 连接句柄
  private var handle: OpaquePointer?

  /// 是否已配置数据库参数（PRAGMA）
  private var didConfigurePragmas = false

  /// 是否已执行迁移
  private var didRunMigrations = false

  /// 初始化数据库管理器
  ///
  /// - Parameter databaseURL: 数据库文件路径（可选）
  ///   - 提供路径：使用指定路径（主要用于测试）
  ///   - nil：使用默认路径（Application Support 目录）
  init(databaseURL: URL? = nil) {
    let fm = FileManager.default
    if let databaseURL {
      self.databaseURL = databaseURL
    } else {
      // 获取 Application Support 目录
      let appSupport = try? fm.url(
        for: .applicationSupportDirectory,
        in: .userDomainMask,
        appropriateFor: nil,
        create: true
      )
      let bundleID = Bundle.main.bundleIdentifier ?? "com.picser.app"
      let folder = (appSupport ?? fm.temporaryDirectory).appendingPathComponent(bundleID, isDirectory: true)

      // 确保目录存在
      if !fm.fileExists(atPath: folder.path) {
        try? fm.createDirectory(at: folder, withIntermediateDirectories: true)
      }

      self.databaseURL = folder.appendingPathComponent("tags.sqlite3")
    }
  }

  /// 清理资源
  ///
  /// 确保在对象销毁时关闭数据库连接，避免资源泄漏。
  deinit {
    if let handle {
      sqlite3_close(handle)
    }
  }

  // MARK: - Public API

  /// 执行数据库操作
  ///
  /// 唯一的公开方法，所有数据库操作都通过此方法执行。
  /// 自动处理连接建立、迁移执行等准备工作。
  ///
  /// 执行流程：
  /// 1. 确保数据库连接已建立（首次调用会打开数据库）
  /// 2. 确保数据库迁移已执行（首次调用会执行所有待执行的迁移）
  /// 3. 执行传入的操作闭包
  ///
  /// 并发安全：
  /// - 由于 actor 的特性，多个调用会自动排队执行
  /// - 即使从多个 Task 并发调用，也能保证串行执行
  ///
  /// - Parameter block: 数据库操作闭包，接收 SQLite 连接句柄
  /// - Returns: 操作闭包的返回值
  /// - Throws: 连接错误、迁移错误或操作闭包抛出的错误
  func perform<T>(_ block: (OpaquePointer) throws -> T) async throws -> T {
    try await ensureConnection()
    try await runMigrationsIfNeeded()
    guard let handle else {
      throw TaggingDatabaseError.uninitialized
    }
    // 对外暴露串行化入口，调用方无需关心并发控制
    return try block(handle)
  }

  // MARK: - Connection & Migration

  /// 确保数据库连接已建立
  ///
  /// 如果连接尚未建立，调用 openIfNeeded() 打开数据库。
  private func ensureConnection() async throws {
    if handle == nil {
      try await openIfNeeded()
    }
  }

  /// 打开数据库连接
  ///
  /// 打开标志：
  /// - SQLITE_OPEN_CREATE：文件不存在时自动创建
  /// - SQLITE_OPEN_READWRITE：可读可写
  /// - SQLITE_OPEN_FULLMUTEX：完全多线程安全模式
  ///
  /// 打开后立即配置数据库参数（PRAGMA）。
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

  /// 如果需要，执行数据库迁移
  ///
  /// 使用布尔标志确保迁移只执行一次（每个 actor 实例的生命周期内）。
  private func runMigrationsIfNeeded() async throws {
    guard !didRunMigrations else { return }
    try await migrateIfNeeded()
    didRunMigrations = true
  }

  /// 执行数据库迁移
  ///
  /// 迁移流程：
  /// 1. 查询当前数据库版本号（user_version）
  /// 2. 按版本号排序所有迁移脚本
  /// 3. 执行版本号大于当前版本的所有迁移
  /// 4. 每个迁移执行后，更新 user_version
  ///
  /// 增量迁移设计：
  /// - 只执行尚未应用的迁移，不会重复执行
  /// - 适合增量发布和数据库升级
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

  /// 执行 SQL 语句
  ///
  /// 使用 sqlite3_exec 执行单个 SQL 语句，不返回查询结果。
  /// 适用于 DDL（CREATE、ALTER）和 DML（INSERT、UPDATE、DELETE）语句。
  ///
  /// - Parameters:
  ///   - sql: SQL 语句
  ///   - db: 数据库连接句柄
  /// - Throws: 执行失败时抛出 TaggingDatabaseError.executionFailed
  private func execute(_ sql: String, db: OpaquePointer) throws {
    var errorMessage: UnsafeMutablePointer<Int8>?
    let result = sqlite3_exec(db, sql, nil, nil, &errorMessage)
    if result != SQLITE_OK {
      let message = errorMessage.map { String(cString: $0) } ?? "未知错误"
      sqlite3_free(errorMessage)
      throw TaggingDatabaseError.executionFailed(code: result, message: message, sql: sql)
    }
  }

  /// 获取当前数据库版本号
  ///
  /// SQLite 的 user_version 是一个用户自定义的整数，用于跟踪数据库模式版本。
  /// 初始值为 0，每次迁移后递增。
  ///
  /// - Returns: 当前数据库版本号（0 表示未迁移的空数据库）
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

  /// 设置数据库版本号
  ///
  /// - Parameters:
  ///   - value: 新的版本号
  ///   - db: 数据库连接句柄
  private func setUserVersion(_ value: Int, db: OpaquePointer) throws {
    try execute("PRAGMA user_version = \(value);", db: db)
  }

  /// 获取最后一次 SQLite 错误消息
  ///
  /// - Parameter handle: 数据库连接句柄（可选，默认使用实例的句柄）
  /// - Returns: 错误消息字符串
  private func lastErrorMessage(from handle: OpaquePointer? = nil) -> String {
    let pointer = handle ?? self.handle
    if let pointer, let cString = sqlite3_errmsg(pointer) {
      return String(cString: cString)
    }
    return "unknown"
  }

  /// 配置数据库参数
  ///
  /// 执行的 PRAGMA 语句：
  /// - **foreign_keys = ON**：启用外键约束，确保数据完整性
  /// - **journal_mode = WAL**：使用 Write-Ahead Logging 模式，提高并发性能
  /// - **synchronous = NORMAL**：平衡性能和安全性（比 FULL 快，比 OFF 安全）
  /// - **temp_store = MEMORY**：临时表存储在内存中，提高排序/分组性能
  /// - **busy_timeout = 5000**：数据库锁定时等待 5 秒后再失败
  ///
  /// 只在首次打开数据库时执行一次。
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

/// 数据库迁移脚本
///
/// 表示单个数据库迁移，包含版本号、名称和执行闭包。
private struct DatabaseMigration {
  /// 迁移版本号（正整数，单调递增）
  let version: Int

  /// 迁移名称（用于调试和日志）
  let name: String

  /// 迁移执行闭包
  /// 接收数据库句柄，执行 DDL 语句创建或修改表结构
  let apply: (OpaquePointer) throws -> Void
}

extension TaggingDatabase {
  /// 所有数据库迁移脚本
  ///
  /// 新增迁移时，只需在数组末尾添加新的 DatabaseMigration。
  /// 版本号必须严格递增，不可重复或跳跃。
  private static let migrations: [DatabaseMigration] = [
    // 版本 1：初始数据库结构
    DatabaseMigration(version: 1, name: "Initial schema") { db in
      let statements = [
        // 标签表
        // - name: 标签名称（唯一约束）
        // - color_hex: 标签颜色（可选，格式 #RRGGBB）
        """
        CREATE TABLE IF NOT EXISTS tags (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL UNIQUE,
          color_hex TEXT,
          created_at REAL NOT NULL,
          updated_at REAL NOT NULL
        );
        """,

        // 图片表
        // - path: 文件完整路径（唯一约束）
        // - file_name: 文件名（不含路径）
        // - directory: 所在目录完整路径
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

        // 图片-标签关联表（多对多）
        // - image_id + tag_id 作为联合主键
        // - ON DELETE CASCADE: 图片或标签删除时，自动删除关联记录
        """
        CREATE TABLE IF NOT EXISTS image_tags (
          image_id INTEGER NOT NULL REFERENCES images(id) ON DELETE CASCADE,
          tag_id INTEGER NOT NULL REFERENCES tags(id) ON DELETE CASCADE,
          created_at REAL NOT NULL,
          PRIMARY KEY(image_id, tag_id)
        );
        """,

        // 索引：按标签名称搜索（不区分大小写）
        "CREATE INDEX IF NOT EXISTS idx_tags_name ON tags(name COLLATE NOCASE);",

        // 索引：查询某个标签被使用的图片（用于标签使用统计）
        "CREATE INDEX IF NOT EXISTS idx_image_tags_tag_id ON image_tags(tag_id);",

        // 索引：查询某张图片的所有标签（用于图片详情页和筛选）
        "CREATE INDEX IF NOT EXISTS idx_image_tags_image_id ON image_tags(image_id);"
      ]
      try runStatements(statements, on: db)
    },

    // 版本 2：添加图片元数据字段
    DatabaseMigration(version: 2, name: "Image metadata columns") { db in
      let statements = [
        // file_identifier: macOS 文件系统的持久化标识（inode）
        "ALTER TABLE images ADD COLUMN file_identifier TEXT;",

        // bookmark: 安全书签数据（Security-Scoped Bookmark）
        "ALTER TABLE images ADD COLUMN bookmark BLOB;",

        // 索引：按 file_identifier 查询（用于文件移动后的追踪）
        "CREATE INDEX IF NOT EXISTS idx_images_file_identifier ON images(file_identifier);"
      ]
      try runStatements(statements, on: db)
    }
  ]

  /// 批量执行 SQL 语句
  ///
  /// - Parameters:
  ///   - statements: SQL 语句数组
  ///   - db: 数据库连接句柄
  /// - Throws: 任何一条语句执行失败时抛出错误
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

/// 数据库错误类型
///
/// 定义所有可能的数据库操作错误，实现 LocalizedError 以提供用户友好的错误消息。
enum TaggingDatabaseError: LocalizedError {
  /// 数据库未初始化（连接尚未建立）
  case uninitialized

  /// 打开数据库失败
  /// - code: SQLite 错误码
  /// - message: 错误详细信息
  case openFailed(code: Int32, message: String)

  /// 执行 SQL 失败
  /// - code: SQLite 错误码
  /// - message: 错误详细信息
  /// - sql: 失败的 SQL 语句
  case executionFailed(code: Int32, message: String, sql: String)

  /// 预编译 SQL 失败
  /// - message: 错误详细信息
  case prepareFailed(message: String)

  /// 本地化错误描述
  ///
  /// 提供用户可读的错误消息，包含 SQLite 错误码和详细信息。
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
