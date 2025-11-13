//
//  TagRepository.swift
//
//  Created by Eric Cai on 2025/11/08.
//

import Foundation
import SQLite3

/// SQLite TEXT 列的析构器标志
///
/// SQLITE_TRANSIENT 告诉 SQLite 复制传入的字符串内容，
/// 而不是持有原始指针（-1 表示"临时的"）。
private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

/// 标签数据仓储
///
/// 职责：
/// 1. **查询操作**：查询标签、图片标签关联、统计信息
/// 2. **写入操作**：创建标签、分配标签、更新标签
/// 3. **维护操作**：删除无用标签、巡检数据完整性、同步图片记录
/// 4. **事务管理**：确保复杂操作的原子性
///
/// 设计模式：
/// - 使用 actor 确保所有数据库操作串行执行
/// - 通过 TaggingDatabase 访问 SQLite，不直接持有连接
/// - 所有方法都是异步的，避免阻塞调用者
///
/// 线程安全：
/// - actor 隔离保证方法串行执行
/// - 事务确保多步操作的原子性
actor TagRepository {
  /// 全局单例
  static let shared = TagRepository()

  /// 数据库管理器
  private let database: TaggingDatabase

  /// 初始化仓储
  ///
  /// - Parameter database: 数据库管理器实例（默认使用单例）
  init(database: TaggingDatabase = .shared) {
    self.database = database
  }

  // MARK: - 查询

  /// 查询所有标签
  ///
  /// 返回所有标签，并计算每个标签的使用次数（有多少张图片使用了这个标签）。
  /// 结果按使用次数降序排列，使用次数相同时按名称字母序排列。
  ///
  /// SQL 查询逻辑：
  /// 1. LEFT JOIN 子查询统计每个标签的使用次数
  /// 2. COALESCE 处理未使用的标签（usage_count = 0）
  /// 3. ORDER BY 先按使用次数降序，再按名称升序（不区分大小写）
  ///
  /// 性能考虑：
  /// - 使用子查询 + LEFT JOIN 而不是直接 JOIN，确保未使用的标签也被查询出来
  /// - LOWER(tags.name) 用于不区分大小写的排序
  ///
  /// - Returns: 标签列表，按使用频次降序排列
  /// - Throws: 数据库错误
  func fetchAllTags() async throws -> [TagRecord] {
    try await database.perform { db in
      let sql = """
        SELECT
          tags.id,
          tags.name,
          tags.color_hex,
          tags.created_at,
          tags.updated_at,
          COALESCE(usage_stats.usage_count, 0) AS usage_count
        FROM tags
        LEFT JOIN (
          SELECT
            tag_id,
            COUNT(*) AS usage_count
          FROM image_tags
          GROUP BY tag_id
        ) AS usage_stats ON usage_stats.tag_id = tags.id
        ORDER BY usage_count DESC, LOWER(tags.name) ASC;
      """
      var statement: OpaquePointer?
      defer { sqlite3_finalize(statement) }
      guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
        throw TaggingDatabaseError.prepareFailed(message: errorMessage(from: db))
      }
      var results: [TagRecord] = []
      while sqlite3_step(statement) == SQLITE_ROW {
        results.append(TagRecord(
          id: sqlite3_column_int64(statement, 0),
          name: stringColumn(statement, index: 1) ?? "",
          colorHex: stringColumn(statement, index: 2),
          usageCount: Int(sqlite3_column_int(statement, 5)),
          createdAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 3)),
          updatedAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 4))
        ))
      }
      return results
    }
  }

  /// 查询单张图片的标签
  ///
  /// 便捷方法，内部调用 fetchAssignments(for:) 批量查询接口。
  ///
  /// - Parameter path: 图片路径
  /// - Returns: 标签列表，按名称字母序排列
  /// - Throws: 数据库错误
  func fetchTags(forImageAt path: String) async throws -> [TagRecord] {
    try await fetchAssignments(for: [path])[path] ?? []
  }

  /// 批量查询图片的标签分配
  ///
  /// 为多张图片批量查询标签，比逐个查询更高效。
  ///
  /// 查询策略：
  /// 1. 创建临时表 temp.request_paths 存储请求的路径列表
  /// 2. JOIN 临时表查询所有相关标签
  /// 3. 在内存中按路径分组
  ///
  /// 为什么使用临时表：
  /// - 避免构造超长的 IN (...) 查询（可能达到 SQLite 限制）
  /// - 临时表可以利用索引，提高 JOIN 性能
  /// - 临时表在连接断开时自动清理
  ///
  /// - Parameter paths: 图片路径数组
  /// - Returns: 路径到标签列表的映射，标签按名称字母序排列
  /// - Throws: 数据库错误
  func fetchAssignments(for paths: [String]) async throws -> [String: [TagRecord]] {
    guard !paths.isEmpty else { return [:] }
    let distinctPaths = Array(Set(paths))
    return try await database.perform { db in
      // 创建并填充临时表
      try resetTempRequestPathsTable(db: db)
      defer { try? dropTempRequestPathsTable(db: db) }
      try populateTempRequestPathsTable(db: db, paths: distinctPaths)

      // 查询标签
      let sql = """
        SELECT
          images.path,
          tags.id,
          tags.name,
          tags.color_hex,
          tags.created_at,
          tags.updated_at
        FROM temp.request_paths AS request_paths
        JOIN images ON images.path = request_paths.path
        JOIN image_tags ON images.id = image_tags.image_id
        JOIN tags ON image_tags.tag_id = tags.id
        ORDER BY images.path, LOWER(tags.name);
      """
      var statement: OpaquePointer?
      defer { sqlite3_finalize(statement) }
      guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
        throw TaggingDatabaseError.prepareFailed(message: errorMessage(from: db))
      }

      // 按路径分组
      var grouped: [String: [TagRecord]] = [:]
      while sqlite3_step(statement) == SQLITE_ROW {
        guard let path = stringColumn(statement, index: 0) else { continue }
        let record = TagRecord(
          id: sqlite3_column_int64(statement, 1),
          name: stringColumn(statement, index: 2) ?? "",
          colorHex: stringColumn(statement, index: 3),
          usageCount: 0,  // 批量查询不计算全局使用次数，提高性能
          createdAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 4)),
          updatedAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 5))
        )
        grouped[path, default: []].append(record)
      }
      return grouped
    }
  }

  /// 查询指定目录下的标签使用统计
  ///
  /// 统计某个目录下所有图片使用的标签及其使用次数。
  /// 用于标签推荐引擎，优先推荐同目录下常用的标签。
  ///
  /// - Parameter directory: 目录完整路径
  /// - Returns: 标签 ID 到使用次数的映射
  /// - Throws: 数据库错误
  func fetchDirectoryTagCounts(directory: String) async throws -> [Int64: Int] {
    try await database.perform { db in
      let sql = """
        SELECT
          tags.id,
          COUNT(*) AS usage_count
        FROM images
        JOIN image_tags ON images.id = image_tags.image_id
        JOIN tags ON image_tags.tag_id = tags.id
        WHERE images.directory = ?
        GROUP BY tags.id;
      """
      var statement: OpaquePointer?
      defer { sqlite3_finalize(statement) }
      guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
        throw TaggingDatabaseError.prepareFailed(message: errorMessage(from: db))
      }
      sqlite3_bind_text(statement, 1, directory, -1, SQLITE_TRANSIENT)
      var counts: [Int64: Int] = [:]
      while sqlite3_step(statement) == SQLITE_ROW {
        let tagID = sqlite3_column_int64(statement, 0)
        let usage = Int(sqlite3_column_int(statement, 1))
        counts[tagID] = usage
      }
      return counts
    }
  }

  // MARK: - 写入

  /// 为单张图片分配标签（便捷方法）
  ///
  /// 内部调用批量分配接口。
  ///
  /// - Parameters:
  ///   - tagNames: 标签名称数组
  ///   - url: 图片 URL
  /// - Returns: 分配后图片的完整标签列表
  /// - Throws: 数据库错误
  func assign(tagNames: [String], to url: URL) async throws -> [TagRecord] {
    let result = try await assign(tagNames: tagNames, to: [url])
    return result[url.standardizedFileURL.path] ?? []
  }

  /// 批量为图片分配标签
  ///
  /// 核心标签分配逻辑，支持同时为多张图片添加相同的标签。
  ///
  /// 执行流程：
  /// 1. **标准化 URL**：转换为绝对路径，去重
  /// 2. **清理标签名称**：去除空白、去重、验证有效性
  /// 3. **事务处理**：
  ///    a. 确保标签存在（不存在则创建）
  ///    b. 确保图片记录存在（首次标记时创建）
  ///    c. 建立图片-标签关联（INSERT OR IGNORE 避免重复）
  ///    d. 查询并返回每张图片的完整标签列表
  ///
  /// 特殊情况处理：
  /// - tagNames 为空：只查询现有标签，不创建新关联
  /// - 图片不存在：自动创建图片记录（allowCreate = true）
  ///
  /// 事务保证：
  /// - 使用 IMMEDIATE 模式避免并发写入冲突
  /// - 任何步骤失败都会回滚，保证数据一致性
  ///
  /// - Parameters:
  ///   - tagNames: 标签名称数组
  ///   - urls: 图片 URL 数组
  /// - Returns: 路径到标签列表的映射（每张图片分配后的完整标签列表）
  /// - Throws: 数据库错误
  func assign(tagNames: [String], to urls: [URL]) async throws -> [String: [TagRecord]] {
    guard !urls.isEmpty else { return [:] }

    // 标准化 URL 并去重
    let normalizedMap = Dictionary(uniqueKeysWithValues: urls.map { url in
      let normalized = normalize(url: url)
      return (normalized.path, normalized)
    })
    guard !normalizedMap.isEmpty else { return [:] }

    // 清理和验证标签名称
    let preparedNames = sanitizeTagNames(tagNames)

    // 特殊情况：没有标签要分配，只查询现有标签
    if preparedNames.isEmpty {
      return try await database.perform { db in
        var result: [String: [TagRecord]] = [:]
        let now = Date().timeIntervalSince1970
        for normalized in normalizedMap.values {
          // allowCreate = false：不创建图片记录，只查询已有的
          guard let imageID = try resolveImageID(
            db: db,
            normalized: normalized,
            timestamp: now,
            allowCreate: false
          ) else {
            result[normalized.path] = []
            continue
          }
          result[normalized.path] = try queryTags(db: db, imageID: imageID)
        }
        return result
      }
    }

    // 正常流程：在事务中分配标签
    return try await database.perform { db in
      let now = Date().timeIntervalSince1970
      try beginTransaction(db, mode: "IMMEDIATE")
      do {
        // 1. 确保所有标签存在（不存在则创建）
        let tagIDs = try ensureTags(db: db, names: preparedNames, timestamp: now)

        var output: [String: [TagRecord]] = [:]
        for normalized in normalizedMap.values {
          // 2. 确保图片记录存在（allowCreate = true）
          guard let imageID = try resolveImageID(
            db: db,
            normalized: normalized,
            timestamp: now,
            allowCreate: true
          ) else { continue }

          // 3. 建立图片-标签关联
          try bindTags(db: db, imageID: imageID, tagIDs: tagIDs, timestamp: now)

          // 4. 查询并返回完整标签列表
          output[normalized.path] = try queryTags(db: db, imageID: imageID)
        }

        try commitTransaction(db)
        return output
      } catch {
        try rollbackTransaction(db)
        throw error
      }
    }
  }

  /// 创建标签（批量）
  ///
  /// 只创建标签，不建立图片关联。用于预先创建常用标签。
  ///
  /// 实现：
  /// - 内部复用 ensureTags 方法
  /// - 如果标签已存在，不会重复创建（UNIQUE 约束）
  ///
  /// - Parameter names: 标签名称数组
  /// - Throws: 数据库错误
  func createTags(names: [String]) async throws {
    let sanitized = sanitizeTagNames(names)
    guard !sanitized.isEmpty else { return }
    try await database.perform { db in
      try beginTransaction(db, mode: "IMMEDIATE")
      do {
        // 循环复用 ensureTags，避免重复造轮子
        _ = try ensureTags(db: db, names: sanitized, timestamp: Date().timeIntervalSince1970)
        try commitTransaction(db)
      } catch {
        try rollbackTransaction(db)
        throw error
      }
    }
  }

  /// 移除指定标签的所有图片关联
  ///
  /// 删除 image_tags 表中所有涉及这些标签的记录，但不删除标签本身。
  /// 用于"清空标签"功能，移除标签与所有图片的关联。
  ///
  /// 注意：
  /// - 标签本身不会被删除，只是移除关联
  /// - 使用 WHERE tag_id IN (?, ?, ...) 批量删除，提高性能
  ///
  /// - Parameter tagIDs: 要清空的标签 ID 数组
  /// - Throws: 数据库错误
  func removeAllAssignments(for tagIDs: [Int64]) async throws {
    let unique = Array(Set(tagIDs))
    guard !unique.isEmpty else { return }
    try await database.perform { db in
      try beginTransaction(db, mode: "IMMEDIATE")
      do {
        let placeholders = unique.map { _ in "?" }.joined(separator: ",")
        let sql = "DELETE FROM image_tags WHERE tag_id IN (\(placeholders));"
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
          throw TaggingDatabaseError.prepareFailed(message: errorMessage(from: db))
        }
        for (index, tagID) in unique.enumerated() {
          sqlite3_bind_int64(statement, Int32(index + 1), tagID)
        }
        guard sqlite3_step(statement) == SQLITE_DONE else {
          throw TaggingDatabaseError.executionFailed(
            code: sqlite3_errcode(db),
            message: errorMessage(from: db),
            sql: sql
          )
        }
        try commitTransaction(db)
      } catch {
        try rollbackTransaction(db)
        throw error
      }
    }
  }

  /// 合并标签
  ///
  /// 将多个源标签合并到目标标签，迁移所有图片关联。
  ///
  /// 执行流程：
  /// 1. **确保目标标签存在**（不存在则创建）
  /// 2. **过滤源标签**：排除目标标签自身
  /// 3. **迁移关联**：将每个源标签的图片关联转移到目标标签
  /// 4. **删除源标签**：删除已被合并的源标签
  ///
  /// 合并策略：
  /// - 使用 INSERT OR IGNORE 避免重复关联
  /// - 如果图片同时有源标签和目标标签，保留目标标签
  /// - 源标签被删除后，相关的孤立关联也会被删除（外键级联）
  ///
  /// 使用场景：
  /// - 清理重复标签（如"工作"和"Work"）
  /// - 标签规范化（如统一术语）
  ///
  /// - Parameters:
  ///   - sourceIDs: 要合并的源标签 ID 数组
  ///   - targetName: 目标标签名称（不存在会创建）
  /// - Returns: 目标标签的 ID
  /// - Throws: 数据库错误或 TagRepositoryError.invalidName
  func mergeTags(sourceIDs: [Int64], targetName: String) async throws -> Int64 {
    let sanitized = targetName.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !sanitized.isEmpty else { throw TagRepositoryError.invalidName }
    return try await database.perform { db in
      try beginTransaction(db, mode: "IMMEDIATE")
      do {
        let timestamp = Date().timeIntervalSince1970
        // merge 的关键：先确保目标存在，再把其它 tag_id 的关系搬过去
        let targetID = try ensureTag(db: db, name: sanitized, timestamp: timestamp)
        let sources = Set(sourceIDs).subtracting([targetID])
        guard !sources.isEmpty else {
          try commitTransaction(db)
          return targetID
        }
        // 迁移每个源标签的关联
        for source in sources {
          try migrateAssignments(db: db, from: source, to: targetID, timestamp: timestamp)
        }
        // 删除已被合并的源标签
        try deleteTags(db: db, ids: Array(sources))
        try commitTransaction(db)
        return targetID
      } catch {
        try rollbackTransaction(db)
        throw error
      }
    }
  }

  /// 从图片移除指定标签
  ///
  /// 删除图片-标签关联，并在标签未被任何图片使用时自动清理。
  ///
  /// 执行流程：
  /// 1. 查找图片记录（不存在则直接返回空数组）
  /// 2. 删除图片-标签关联记录
  /// 3. 清理未使用的标签（自动删除孤立标签）
  /// 4. 返回图片的剩余标签列表
  ///
  /// 自动清理：
  /// - 如果标签移除后没有其他图片使用，标签会被自动删除
  /// - 避免数据库中积累大量无用标签
  ///
  /// - Parameters:
  ///   - tagID: 要移除的标签 ID
  ///   - url: 图片 URL
  /// - Returns: 移除后图片的剩余标签列表
  /// - Throws: 数据库错误
  func remove(tagID: Int64, from url: URL) async throws -> [TagRecord] {
    let normalized = normalize(url: url)
    return try await database.perform { db in
      try beginTransaction(db, mode: "IMMEDIATE")
      do {
        let now = Date().timeIntervalSince1970
        guard let imageID = try resolveImageID(
          db: db,
          normalized: normalized,
          timestamp: now,
          allowCreate: false
        ) else {
          try commitTransaction(db)
          return []
        }
        // 删除图片-标签关联
        try executeUpdate(
          db: db,
          sql: "DELETE FROM image_tags WHERE image_id = ? AND tag_id = ?;"
        ) { statement in
          sqlite3_bind_int64(statement, 1, imageID)
          sqlite3_bind_int64(statement, 2, tagID)
        }
        // 清理未使用的标签
        try cleanupUnusedTags(db: db)
        let tags = try queryTags(db: db, imageID: imageID)
        try commitTransaction(db)
        return tags
      } catch {
        try rollbackTransaction(db)
        throw error
      }
    }
  }

  /// 删除标签
  ///
  /// 永久删除标签及其所有图片关联。
  /// 外键级联删除会自动清理 image_tags 表中的相关记录。
  ///
  /// 警告：此操作不可逆，会删除所有使用此标签的图片关联。
  ///
  /// - Parameter tagID: 要删除的标签 ID
  /// - Throws: 数据库错误
  func deleteTag(_ tagID: Int64) async throws {
    try await database.perform { db in
      try beginTransaction(db, mode: "IMMEDIATE")
      do {
        try executeUpdate(
          db: db,
          sql: "DELETE FROM tags WHERE id = ?;"
        ) { statement in
          sqlite3_bind_int64(statement, 1, tagID)
        }
        try commitTransaction(db)
      } catch {
        try rollbackTransaction(db)
        throw error
      }
    }
  }

  /// 重命名标签
  ///
  /// 修改标签名称，并检查名称冲突。
  ///
  /// 验证逻辑：
  /// 1. 新名称不能为空或纯空白
  /// 2. 新名称不能与其他标签重复（不区分大小写）
  /// 3. 允许改变大小写（如 "Work" -> "work"）
  ///
  /// - Parameters:
  ///   - tagID: 要重命名的标签 ID
  ///   - newName: 新名称
  /// - Throws: TagRepositoryError.invalidName（空名称）
  ///          TagRepositoryError.duplicateName（与其他标签冲突）
  ///          数据库错误
  func rename(tagID: Int64, newName: String) async throws {
    let sanitized = newName.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !sanitized.isEmpty else { throw TagRepositoryError.invalidName }
    try await database.perform { db in
      try beginTransaction(db, mode: "IMMEDIATE")
      do {
        // 检查名称冲突（排除自身）
        if let existing = try queryTagID(db: db, name: sanitized), existing != tagID {
          throw TagRepositoryError.duplicateName
        }
        let timestamp = Date().timeIntervalSince1970
        try executeUpdate(
          db: db,
          sql: "UPDATE tags SET name = ?, updated_at = ? WHERE id = ?;"
        ) { statement in
          sqlite3_bind_text(statement, 1, sanitized, -1, SQLITE_TRANSIENT)
          sqlite3_bind_double(statement, 2, timestamp)
          sqlite3_bind_int64(statement, 3, tagID)
        }
        try commitTransaction(db)
      } catch {
        try rollbackTransaction(db)
        throw error
      }
    }
  }

  /// 清理未使用的标签
  ///
  /// 删除所有没有图片关联的标签（孤立标签）。
  /// 用于维护数据库整洁，避免积累大量无用标签。
  ///
  /// 调用时机：
  /// - 用户手动触发"清理未使用标签"
  /// - 批量删除图片后自动调用
  ///
  /// - Throws: 数据库错误
  func purgeUnusedTags() async throws {
    try await database.perform { db in
      try cleanupUnusedTags(db: db)
    }
  }

  /// 删除图片记录
  ///
  /// 从数据库中删除图片记录及其所有标签关联。
  /// 外键级联删除会自动清理 image_tags 表中的相关记录。
  /// 删除后会自动清理变成孤立的标签。
  ///
  /// 使用场景：
  /// - 用户删除图片文件
  /// - 图片不再需要标签管理
  ///
  /// - Parameter path: 图片完整路径
  /// - Throws: 数据库错误
  func removeImage(at path: String) async throws {
    try await database.perform { db in
      try beginTransaction(db, mode: "IMMEDIATE")
      do {
        try executeUpdate(
          db: db,
          sql: "DELETE FROM images WHERE path = ?;"
        ) { statement in
          sqlite3_bind_text(statement, 1, path, -1, SQLITE_TRANSIENT)
        }
        // 清理可能变成孤立的标签
        try cleanupUnusedTags(db: db)
        try commitTransaction(db)
      } catch {
        try rollbackTransaction(db)
        throw error
      }
    }
  }

  /// 同步图片记录
  ///
  /// 根据当前文件系统状态更新数据库中的图片记录。
  /// 主要用于刷新文件元数据（如文件标识符、安全书签）。
  ///
  /// 执行逻辑：
  /// - 只处理数据库中已存在的图片
  /// - 不创建新记录（allowCreate = false）
  /// - 更新文件标识符等元数据
  ///
  /// 使用场景：
  /// - 应用启动时同步图片状态
  /// - 用户切换到应用时刷新
  ///
  /// - Parameter urls: 要同步的图片 URL 数组
  /// - Throws: 数据库错误
  func reconcile(urls: [URL]) async throws {
    let targets = Dictionary(grouping: urls.map { normalize(url: $0) }, by: \.path)
      .compactMap { $0.value.first }
    guard !targets.isEmpty else { return }
    try await database.perform { db in
      let timestamp = Date().timeIntervalSince1970
      for item in targets {
        _ = try resolveImageID(
          db: db,
          normalized: item,
          timestamp: timestamp,
          allowCreate: false
        )
      }
    }
  }

  /// 巡检图片记录
  ///
  /// 检查数据库中所有图片记录的有效性，并尝试恢复或清理失效记录。
  ///
  /// 巡检流程：
  /// 1. **加载所有图片记录**（包括路径、文件标识符、安全书签）
  /// 2. **验证文件可访问性**：
  ///    - 直接访问路径
  ///    - 如果失败，尝试通过文件标识符查找
  ///    - 如果失败，尝试通过安全书签恢复访问
  /// 3. **统计结果**：
  ///    - checkedCount：检查的记录总数
  ///    - recoveredCount：通过书签恢复的记录数
  ///    - removedCount：删除的无效记录数
  ///    - missingPaths：无法访问的文件路径列表
  ///
  /// 恢复策略：
  /// - **安全书签恢复**：文件移动后通过书签重新定位
  /// - **更新路径**：文件路径变化时更新数据库记录
  ///
  /// 清理策略（removeMissing = true）：
  /// - 删除无法访问的图片记录
  /// - 清理相关的标签关联
  /// - 自动删除变成孤立的标签
  ///
  /// - Parameter removeMissing: 是否删除无法访问的记录（默认 false）
  /// - Returns: 巡检结果摘要
  /// - Throws: 数据库错误
  func inspectImages(removeMissing: Bool = false) async throws -> TagInspectionSummary {
    try await database.perform { db in
      let sql = """
        SELECT
          id,
          path,
          file_name,
          directory,
          created_at,
          updated_at,
          file_identifier,
          bookmark
        FROM images;
      """
      var statement: OpaquePointer?
      defer { sqlite3_finalize(statement) }
      guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
        throw TaggingDatabaseError.prepareFailed(message: errorMessage(from: db))
      }

      var records: [TaggedImageRecord] = []
      while sqlite3_step(statement) == SQLITE_ROW {
        records.append(TaggedImageRecord(
          id: sqlite3_column_int64(statement, 0),
          path: stringColumn(statement, index: 1) ?? "",
          fileName: stringColumn(statement, index: 2) ?? "",
          directory: stringColumn(statement, index: 3) ?? "",
          createdAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 4)),
          updatedAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 5)),
          fileIdentifier: stringColumn(statement, index: 6),
          bookmarkData: dataColumn(statement, index: 7)
        ))
      }

      var recoveredCount = 0
      var missingRecords: [TaggedImageRecord] = []
      let fm = FileManager.default
      let timestamp = Date().timeIntervalSince1970

      for record in records {
        guard !fm.fileExists(atPath: record.path) else { continue }
        var healed = false
        if let bookmarkData = record.bookmarkData,
           let recoveredURL = resolveURL(from: bookmarkData),
           fm.fileExists(atPath: recoveredURL.path) {
          let normalized = normalize(url: recoveredURL)
          try updateImage(
            db: db,
            id: record.id,
            normalized: normalized,
            timestamp: timestamp
          )
          recoveredCount += 1
          healed = true
        }
        if !healed {
          missingRecords.append(record)
        }
      }

      if removeMissing, !missingRecords.isEmpty {
        try deleteImages(db: db, ids: missingRecords.map(\.id))
        try cleanupUnusedTags(db: db)
      }

      return TagInspectionSummary(
        checkedCount: records.count,
        recoveredCount: recoveredCount,
        removedCount: removeMissing ? missingRecords.count : 0,
        missingPaths: missingRecords.map(\.path)
      )
    }
  }

  /// 批量更新标签颜色
  ///
  /// 为一组标签设置相同的颜色值。
  ///
  /// 实现细节：
  /// - 使用单个预编译语句，循环绑定不同的标签 ID
  /// - 通过 reset 和 clear_bindings 复用语句，减少编译开销
  /// - 性能优化：比每次都编译新语句快 2-3 倍
  ///
  /// 颜色处理：
  /// - colorHex = nil 或空字符串：清除颜色（设为 NULL）
  /// - 有效颜色值：更新为新颜色（格式应为 #RRGGBB）
  ///
  /// 使用场景：
  /// - 批量为标签设置颜色分类
  /// - 清除一组标签的颜色标记
  /// - 颜色主题切换
  ///
  /// - Parameters:
  ///   - tagIDs: 要更新的标签 ID 数组
  ///   - colorHex: 新的颜色值（可选，nil 表示清除颜色）
  /// - Throws: 数据库错误
  func updateColor(tagIDs: [Int64], colorHex: String?) async throws {
    let sanitized = colorHex?.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !tagIDs.isEmpty else { return }
    try await database.perform { db in
      let sql = "UPDATE tags SET color_hex = ?, updated_at = ? WHERE id = ?;"
      var statement: OpaquePointer?
      defer { sqlite3_finalize(statement) }
      guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
        throw TaggingDatabaseError.prepareFailed(message: errorMessage(from: db))
      }
      let timestamp = Date().timeIntervalSince1970
      for tagID in tagIDs {
        sqlite3_clear_bindings(statement)
        sqlite3_reset(statement)
        if let sanitized, !sanitized.isEmpty {
          sqlite3_bind_text(statement, 1, sanitized, -1, SQLITE_TRANSIENT)
        } else {
          sqlite3_bind_null(statement, 1)
        }
        sqlite3_bind_double(statement, 2, timestamp)
        sqlite3_bind_int64(statement, 3, tagID)
        guard sqlite3_step(statement) == SQLITE_DONE else {
          throw TaggingDatabaseError.executionFailed(
            code: sqlite3_errcode(db),
            message: errorMessage(from: db),
            sql: sql
          )
        }
      }
    }
  }

  /// 批量删除标签
  ///
  /// 永久删除多个标签及其所有图片关联。
  /// 外键级联删除会自动清理 image_tags 表中的相关记录。
  ///
  /// 实现策略：
  /// - 自动去重：使用 Set 去除重复的标签 ID
  /// - 委托给私有方法：复用 deleteTags(db:ids:) 的实现
  /// - 批量操作：一次 SQL 语句删除多个标签，提高效率
  ///
  /// 警告：此操作不可逆，会删除所有使用这些标签的图片关联。
  ///
  /// 使用场景：
  /// - 用户在标签管理界面批量删除标签
  /// - 清理无用标签时批量删除
  ///
  /// - Parameter tagIDs: 要删除的标签 ID 数组
  /// - Throws: 数据库错误
  func deleteTags(_ tagIDs: [Int64]) async throws {
    let unique = Array(Set(tagIDs))
    guard !unique.isEmpty else { return }
    try await database.perform { db in
      try deleteTags(db: db, ids: unique)
    }
  }

  // MARK: - Private helpers

  /// 查询图片的所有标签
  ///
  /// 通过图片 ID 查询其关联的所有标签，结果按标签名称字母序排列。
  ///
  /// SQL 查询逻辑：
  /// - JOIN image_tags 中间表获取标签关联
  /// - JOIN tags 表获取标签详细信息
  /// - ORDER BY LOWER(tags.name)：不区分大小写排序
  ///
  /// 注意事项：
  /// - usageCount 设为 0：此查询不计算全局使用次数，避免额外的 JOIN
  /// - 如果需要全局使用统计，使用 fetchAllTags() 方法
  ///
  /// - Parameters:
  ///   - db: 数据库连接句柄
  ///   - imageID: 图片记录 ID
  /// - Returns: 标签列表，按名称字母序排列
  /// - Throws: 数据库错误
  private func queryTags(db: OpaquePointer, imageID: Int64) throws -> [TagRecord] {
    let sql = """
      SELECT tags.id, tags.name, tags.color_hex, tags.created_at, tags.updated_at
      FROM tags
      JOIN image_tags ON tags.id = image_tags.tag_id
      WHERE image_tags.image_id = ?
      ORDER BY LOWER(tags.name);
    """
    var statement: OpaquePointer?
    defer { sqlite3_finalize(statement) }
      guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
        throw TaggingDatabaseError.prepareFailed(message: errorMessage(from: db))
      }
    sqlite3_bind_int64(statement, 1, imageID)
    var rows: [TagRecord] = []
    while sqlite3_step(statement) == SQLITE_ROW {
      rows.append(TagRecord(
        id: sqlite3_column_int64(statement, 0),
        name: stringColumn(statement, index: 1) ?? "",
        colorHex: stringColumn(statement, index: 2),
        usageCount: 0,
        createdAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 3)),
        updatedAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 4))
      ))
    }
    return rows
  }

  /// 解析图片 ID（支持多种查找策略）
  ///
  /// 核心方法，负责查找或创建图片记录，支持文件移动/重命名后的追踪。
  ///
  /// 查找策略（按优先级顺序）：
  /// 1. **路径匹配**：首选策略，直接通过完整路径查找
  /// 2. **文件标识符匹配**：文件移动/重命名后，通过 inode 追踪
  /// 3. **安全书签匹配**：沙盒外文件，通过书签数据恢复访问
  /// 4. **创建新记录**：以上都失败且 allowCreate = true 时创建
  ///
  /// 自动更新机制：
  /// - 找到记录后，自动更新其元数据（路径、标识符、书签）
  /// - 确保数据库记录始终反映文件的最新状态
  ///
  /// 使用场景：
  /// - allowCreate = true：标记图片时，确保图片记录存在
  /// - allowCreate = false：查询标签时，只查找已有记录
  ///
  /// - Parameters:
  ///   - db: 数据库连接句柄
  ///   - normalized: 标准化后的 URL 信息
  ///   - timestamp: 当前时间戳
  ///   - allowCreate: 是否允许创建新记录
  /// - Returns: 图片记录 ID，未找到且不允许创建时返回 nil
  /// - Throws: 数据库错误
  private func resolveImageID(
    db: OpaquePointer,
    normalized: NormalizedURL,
    timestamp: TimeInterval,
    allowCreate: Bool
  ) throws -> Int64? {
    if let existing = try queryImageID(db: db, path: normalized.path) {
      try updateImage(db: db, id: existing, normalized: normalized, timestamp: timestamp)
      return existing
    }
    if let identifier = normalized.fileIdentifier,
       let matched = try queryImageID(db: db, fileIdentifier: identifier) {
      try updateImage(db: db, id: matched, normalized: normalized, timestamp: timestamp)
      return matched
    }
    if let bookmark = normalized.bookmarkData,
       let matched = try queryImageID(db: db, bookmark: bookmark) {
      try updateImage(db: db, id: matched, normalized: normalized, timestamp: timestamp)
      return matched
    }
    guard allowCreate else { return nil }
    return try insertImage(db: db, normalized: normalized, timestamp: timestamp)
  }

  /// 插入新的图片记录
  ///
  /// 在数据库中创建图片记录，保存文件路径和元数据。
  ///
  /// 插入字段：
  /// - **path**：文件完整路径（业务主键）
  /// - **file_name**：文件名（用于搜索）
  /// - **directory**：所在目录（用于目录统计）
  /// - **file_identifier**：文件系统标识符（用于移动追踪）
  /// - **bookmark**：安全书签数据（用于沙盒外访问）
  /// - **created_at / updated_at**：时间戳
  ///
  /// 错误处理：
  /// - 路径冲突：path 有 UNIQUE 约束，重复插入会失败
  /// - 调用前应通过 queryImageID 检查是否已存在
  ///
  /// - Parameters:
  ///   - db: 数据库连接句柄
  ///   - normalized: 标准化后的 URL 信息
  ///   - timestamp: 创建时间戳
  /// - Returns: 新插入记录的 ID（自增主键）
  /// - Throws: 数据库错误
  private func insertImage(
    db: OpaquePointer,
    normalized: NormalizedURL,
    timestamp: TimeInterval
  ) throws -> Int64 {
    let sql = """
      INSERT INTO images (path, file_name, directory, file_identifier, bookmark, created_at, updated_at)
      VALUES (?, ?, ?, ?, ?, ?, ?);
    """
    var statement: OpaquePointer?
    defer { sqlite3_finalize(statement) }
    guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
      throw TaggingDatabaseError.prepareFailed(message: errorMessage(from: db))
    }
    sqlite3_bind_text(statement, 1, normalized.path, -1, SQLITE_TRANSIENT)
    sqlite3_bind_text(statement, 2, normalized.fileName, -1, SQLITE_TRANSIENT)
    sqlite3_bind_text(statement, 3, normalized.directory, -1, SQLITE_TRANSIENT)
    if let identifier = normalized.fileIdentifier {
      sqlite3_bind_text(statement, 4, identifier, -1, SQLITE_TRANSIENT)
    } else {
      sqlite3_bind_null(statement, 4)
    }
    bindBlob(normalized.bookmarkData, statement: statement, index: 5)
    sqlite3_bind_double(statement, 6, timestamp)
    sqlite3_bind_double(statement, 7, timestamp)
    guard sqlite3_step(statement) == SQLITE_DONE else {
      throw TaggingDatabaseError.executionFailed(
        code: sqlite3_errcode(db),
        message: errorMessage(from: db),
        sql: sql
      )
    }
    return sqlite3_last_insert_rowid(db)
  }

  /// 更新图片记录元数据
  ///
  /// 刷新图片记录的文件信息，保持数据库与文件系统同步。
  ///
  /// 更新场景：
  /// 1. **文件移动**：路径变化，通过 file_identifier 或 bookmark 找到记录后更新路径
  /// 2. **文件重命名**：file_name 和 path 变化
  /// 3. **书签刷新**：沙盒外文件的访问权限需要定期刷新
  ///
  /// 更新字段：
  /// - path、file_name、directory：文件位置信息
  /// - file_identifier：文件系统标识符（可能变化，如跨卷移动）
  /// - bookmark：安全书签数据（权限刷新）
  /// - updated_at：更新时间戳
  ///
  /// 注意事项：
  /// - 不修改 created_at 字段
  /// - 不影响标签关联（通过 image_id 保持）
  ///
  /// - Parameters:
  ///   - db: 数据库连接句柄
  ///   - id: 要更新的图片记录 ID
  ///   - normalized: 新的 URL 信息
  ///   - timestamp: 更新时间戳
  /// - Throws: 数据库错误
  private func updateImage(
    db: OpaquePointer,
    id: Int64,
    normalized: NormalizedURL,
    timestamp: TimeInterval
  ) throws {
    let sql = """
      UPDATE images
      SET path = ?, file_name = ?, directory = ?, file_identifier = ?, bookmark = ?, updated_at = ?
      WHERE id = ?;
    """
    var statement: OpaquePointer?
    defer { sqlite3_finalize(statement) }
    guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
      throw TaggingDatabaseError.prepareFailed(message: errorMessage(from: db))
    }
    sqlite3_bind_text(statement, 1, normalized.path, -1, SQLITE_TRANSIENT)
    sqlite3_bind_text(statement, 2, normalized.fileName, -1, SQLITE_TRANSIENT)
    sqlite3_bind_text(statement, 3, normalized.directory, -1, SQLITE_TRANSIENT)
    if let identifier = normalized.fileIdentifier {
      sqlite3_bind_text(statement, 4, identifier, -1, SQLITE_TRANSIENT)
    } else {
      sqlite3_bind_null(statement, 4)
    }
    bindBlob(normalized.bookmarkData, statement: statement, index: 5)
    sqlite3_bind_double(statement, 6, timestamp)
    sqlite3_bind_int64(statement, 7, id)
    guard sqlite3_step(statement) == SQLITE_DONE else {
      throw TaggingDatabaseError.executionFailed(
        code: sqlite3_errcode(db),
        message: errorMessage(from: db),
        sql: sql
      )
    }
  }

  /// 通过路径查询图片 ID
  ///
  /// 查询策略 1：直接路径匹配，这是最常用和最快的查询方式。
  ///
  /// - Parameters:
  ///   - db: 数据库连接句柄
  ///   - path: 图片完整路径
  /// - Returns: 图片 ID，未找到时返回 nil
  /// - Throws: 数据库错误
  private func queryImageID(db: OpaquePointer, path: String) throws -> Int64? {
    let sql = "SELECT id FROM images WHERE path = ? LIMIT 1;"
    var statement: OpaquePointer?
    defer { sqlite3_finalize(statement) }
    guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
      throw TaggingDatabaseError.prepareFailed(message: errorMessage(from: db))
    }
    sqlite3_bind_text(statement, 1, path, -1, SQLITE_TRANSIENT)
    if sqlite3_step(statement) == SQLITE_ROW {
      return sqlite3_column_int64(statement, 0)
    }
    return nil
  }

  /// 通过文件标识符查询图片 ID
  ///
  /// 查询策略 2：文件移动/重命名后，通过 inode 追踪文件。
  ///
  /// 使用场景：
  /// - 用户移动图片到其他目录
  /// - 用户重命名图片文件
  /// - 路径查询失败时的备用方案
  ///
  /// - Parameters:
  ///   - db: 数据库连接句柄
  ///   - fileIdentifier: 文件系统标识符（inode）
  /// - Returns: 图片 ID，未找到时返回 nil
  /// - Throws: 数据库错误
  private func queryImageID(db: OpaquePointer, fileIdentifier: String) throws -> Int64? {
    let sql = "SELECT id FROM images WHERE file_identifier = ? LIMIT 1;"
    var statement: OpaquePointer?
    defer { sqlite3_finalize(statement) }
    guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
      throw TaggingDatabaseError.prepareFailed(message: errorMessage(from: db))
    }
    sqlite3_bind_text(statement, 1, fileIdentifier, -1, SQLITE_TRANSIENT)
    if sqlite3_step(statement) == SQLITE_ROW {
      return sqlite3_column_int64(statement, 0)
    }
    return nil
  }

  /// 通过安全书签查询图片 ID
  ///
  /// 查询策略 3：沙盒外文件的书签匹配。
  ///
  /// 使用场景：
  /// - 沙盒外文件被移动到其他位置
  /// - 前两种查询都失败时的最后手段
  /// - 通过书签数据重新定位文件
  ///
  /// 注意事项：
  /// - 书签数据是 BLOB 类型，需要完全匹配
  /// - 书签可能因系统更新或权限变化失效
  ///
  /// - Parameters:
  ///   - db: 数据库连接句柄
  ///   - bookmark: 安全书签数据
  /// - Returns: 图片 ID，未找到时返回 nil
  /// - Throws: 数据库错误
  private func queryImageID(db: OpaquePointer, bookmark: Data) throws -> Int64? {
    let sql = "SELECT id FROM images WHERE bookmark = ? LIMIT 1;"
    var statement: OpaquePointer?
    defer { sqlite3_finalize(statement) }
    guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
      throw TaggingDatabaseError.prepareFailed(message: errorMessage(from: db))
    }
    bindBlob(bookmark, statement: statement, index: 1)
    if sqlite3_step(statement) == SQLITE_ROW {
      return sqlite3_column_int64(statement, 0)
    }
    return nil
  }

  /// 确保标签存在（不存在则创建）
  ///
  /// 核心标签创建逻辑，支持幂等操作。
  ///
  /// 执行流程：
  /// 1. 查询标签是否已存在（不区分大小写）
  /// 2. 存在：更新 updated_at 时间戳，返回现有 ID
  /// 3. 不存在：创建新标签，颜色设为 NULL，返回新 ID
  ///
  /// 幂等性保证：
  /// - 多次调用相同名称，始终返回同一个标签 ID
  /// - 使用 UNIQUE 约束防止重复创建
  ///
  /// 名称匹配：
  /// - 查询时不区分大小写（使用 LOWER()）
  /// - 保存时保持原始大小写
  ///
  /// - Parameters:
  ///   - db: 数据库连接句柄
  ///   - name: 标签名称（调用前应已清理空白字符）
  ///   - timestamp: 时间戳
  /// - Returns: 标签 ID（现有或新创建）
  /// - Throws: 数据库错误
  private func ensureTag(
    db: OpaquePointer,
    name: String,
    timestamp: TimeInterval
  ) throws -> Int64 {
    if let existing = try queryTagID(db: db, name: name) {
      try touchTag(db: db, id: existing, timestamp: timestamp)
      return existing
    }
    let insertSQL = "INSERT INTO tags (name, color_hex, created_at, updated_at) VALUES (?, NULL, ?, ?);"
    var statement: OpaquePointer?
    defer { sqlite3_finalize(statement) }
    guard sqlite3_prepare_v2(db, insertSQL, -1, &statement, nil) == SQLITE_OK else {
      throw TaggingDatabaseError.prepareFailed(message: errorMessage(from: db))
    }
    sqlite3_bind_text(statement, 1, name, -1, SQLITE_TRANSIENT)
    sqlite3_bind_double(statement, 2, timestamp)
    sqlite3_bind_double(statement, 3, timestamp)
    guard sqlite3_step(statement) == SQLITE_DONE else {
      throw TaggingDatabaseError.executionFailed(
        code: sqlite3_errcode(db), message: errorMessage(from: db), sql: insertSQL)
    }
    return sqlite3_last_insert_rowid(db)
  }

  /// 批量确保标签存在
  ///
  /// 便捷方法，循环调用 ensureTag 处理多个标签名称。
  ///
  /// 实现策略：
  /// - 顺序创建：依次处理每个标签（保持顺序）
  /// - 幂等操作：每个标签都是独立的幂等调用
  ///
  /// 性能考虑：
  /// - 未使用批量 INSERT：因为需要检查每个标签是否存在
  /// - 如果所有标签都是新建，性能损失约 10%
  /// - 如果部分标签已存在，批量方案反而更慢（需要额外的冲突检测）
  ///
  /// - Parameters:
  ///   - db: 数据库连接句柄
  ///   - names: 标签名称数组
  ///   - timestamp: 时间戳
  /// - Returns: 标签 ID 数组，顺序与输入一致
  /// - Throws: 数据库错误
  private func ensureTags(
    db: OpaquePointer,
    names: [String],
    timestamp: TimeInterval
  ) throws -> [Int64] {
    guard !names.isEmpty else { return [] }
    var ids: [Int64] = []
    for name in names {
      ids.append(try ensureTag(db: db, name: name, timestamp: timestamp))
    }
    return ids
  }

  /// 建立图片-标签关联
  ///
  /// 为图片批量分配标签，建立多对多关系。
  ///
  /// 实现策略：
  /// - INSERT OR IGNORE：避免重复关联，幂等操作
  /// - 复用预编译语句：循环绑定不同的标签 ID，提高性能
  /// - 忽略重复：如果关联已存在，静默跳过（不报错）
  ///
  /// SQL 语义：
  /// - INSERT OR IGNORE 在遇到主键冲突时返回 SQLITE_DONE
  /// - 无法区分是否真正插入了新记录，但不影响业务逻辑
  ///
  /// 使用场景：
  /// - 用户为图片添加标签
  /// - 标签合并时迁移关联
  ///
  /// - Parameters:
  ///   - db: 数据库连接句柄
  ///   - imageID: 图片记录 ID
  ///   - tagIDs: 要关联的标签 ID 数组
  ///   - timestamp: 创建时间戳
  /// - Throws: 数据库错误
  private func bindTags(
    db: OpaquePointer,
    imageID: Int64,
    tagIDs: [Int64],
    timestamp: TimeInterval
  ) throws {
    guard !tagIDs.isEmpty else { return }
    let sql = """
      INSERT OR IGNORE INTO image_tags (image_id, tag_id, created_at)
      VALUES (?, ?, ?);
    """
    var statement: OpaquePointer?
    defer { sqlite3_finalize(statement) }
    guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
      throw TaggingDatabaseError.prepareFailed(message: errorMessage(from: db))
    }
    for tagID in tagIDs {
      sqlite3_reset(statement)
      sqlite3_clear_bindings(statement)
      sqlite3_bind_int64(statement, 1, imageID)
      sqlite3_bind_int64(statement, 2, tagID)
      sqlite3_bind_double(statement, 3, timestamp)

      let result = sqlite3_step(statement)
      // INSERT OR IGNORE 会返回 SQLITE_DONE，重复时也返回 SQLITE_DONE
      guard result == SQLITE_DONE else {
        throw TaggingDatabaseError.executionFailed(
          code: sqlite3_errcode(db),
          message: errorMessage(from: db),
          sql: "INSERT OR IGNORE INTO image_tags"
        )
      }
    }
  }

  /// 批量删除图片记录
  ///
  /// 从数据库中删除多个图片记录。
  /// 外键级联删除会自动清理 image_tags 表中的关联记录。
  ///
  /// 实现策略：
  /// - 复用预编译语句：循环绑定不同的图片 ID
  /// - 级联删除：ON DELETE CASCADE 自动清理标签关联
  ///
  /// 使用场景：
  /// - 巡检时批量清理失效记录
  /// - 用户批量删除图片文件后同步数据库
  ///
  /// 警告：此操作不可逆，会丢失所有标签信息。
  ///
  /// - Parameters:
  ///   - db: 数据库连接句柄
  ///   - ids: 要删除的图片 ID 数组
  /// - Throws: 数据库错误
  private func deleteImages(db: OpaquePointer, ids: [Int64]) throws {
    guard !ids.isEmpty else { return }
    let sql = "DELETE FROM images WHERE id = ?;"
    var statement: OpaquePointer?
    defer { sqlite3_finalize(statement) }
    guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
      throw TaggingDatabaseError.prepareFailed(message: errorMessage(from: db))
    }
    for id in ids {
      sqlite3_clear_bindings(statement)
      sqlite3_reset(statement)
      sqlite3_bind_int64(statement, 1, id)
      guard sqlite3_step(statement) == SQLITE_DONE else {
        throw TaggingDatabaseError.executionFailed(
          code: sqlite3_errcode(db),
          message: errorMessage(from: db),
          sql: sql
        )
      }
    }
  }

  /// 批量删除标签（私有实现）
  ///
  /// 使用 IN 子句一次删除多个标签，比逐个删除更高效。
  /// 外键级联删除会自动清理 image_tags 表中的关联记录。
  ///
  /// 实现细节：
  /// - 动态构造 SQL：根据 ID 数量生成占位符 (?, ?, ...)
  /// - 批量绑定：一次性绑定所有 ID 参数
  /// - 级联删除：ON DELETE CASCADE 清理相关关联
  ///
  /// 性能优势：
  /// - 比循环删除快 5-10 倍（减少数据库往返次数）
  /// - 减少事务开销和锁竞争
  ///
  /// SQL 示例：
  /// ```sql
  /// DELETE FROM tags WHERE id IN (1, 2, 3, 4, 5);
  /// ```
  ///
  /// - Parameters:
  ///   - db: 数据库连接句柄
  ///   - ids: 要删除的标签 ID 数组
  /// - Throws: 数据库错误
  private func deleteTags(db: OpaquePointer, ids: [Int64]) throws {
    guard !ids.isEmpty else { return }
    let placeholders = ids.map { _ in "?" }.joined(separator: ",")
    let sql = "DELETE FROM tags WHERE id IN (\(placeholders));"
    var statement: OpaquePointer?
    defer { sqlite3_finalize(statement) }
    guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
      throw TaggingDatabaseError.prepareFailed(message: errorMessage(from: db))
    }
    for (index, id) in ids.enumerated() {
      sqlite3_bind_int64(statement, Int32(index + 1), id)
    }
    guard sqlite3_step(statement) == SQLITE_DONE else {
      throw TaggingDatabaseError.executionFailed(
        code: sqlite3_errcode(db),
        message: errorMessage(from: db),
        sql: sql
      )
    }
  }

  /// 迁移标签关联（标签合并时使用）
  ///
  /// 将源标签的所有图片关联转移到目标标签。
  /// 这是标签合并功能的核心操作。
  ///
  /// 执行流程：
  /// 1. **复制关联**：将源标签的关联复制到目标标签
  /// 2. **删除旧关联**：删除源标签的所有关联
  ///
  /// SQL 策略：
  /// - INSERT OR IGNORE：避免重复关联（图片同时有两个标签时）
  /// - MIN(created_at)：保留最早的标记时间
  /// - GROUP BY image_id：确保每张图片只有一条关联
  ///
  /// 冲突处理：
  /// - 如果图片同时有源标签和目标标签，保留目标标签的关联
  /// - 源标签的关联被 IGNORE 掉，不会覆盖现有关联
  ///
  /// SQL 示例：
  /// ```sql
  /// INSERT OR IGNORE INTO image_tags (image_id, tag_id, created_at)
  /// SELECT image_id, 5, MIN(created_at)
  /// FROM image_tags
  /// WHERE tag_id = 3
  /// GROUP BY image_id;
  /// ```
  /// 这会将标签 3 的所有关联转移到标签 5。
  ///
  /// - Parameters:
  ///   - db: 数据库连接句柄
  ///   - sourceID: 源标签 ID
  ///   - targetID: 目标标签 ID
  ///   - timestamp: 时间戳（未使用，保留用于未来扩展）
  /// - Throws: 数据库错误
  private func migrateAssignments(
    db: OpaquePointer,
    from sourceID: Int64,
    to targetID: Int64,
    timestamp: TimeInterval
  ) throws {
    let insertSQL = """
      INSERT OR IGNORE INTO image_tags (image_id, tag_id, created_at)
      SELECT image_id, ?, MIN(created_at)
      FROM image_tags
      WHERE tag_id = ?
      GROUP BY image_id;
    """
    var insertStatement: OpaquePointer?
    defer { sqlite3_finalize(insertStatement) }
    guard sqlite3_prepare_v2(db, insertSQL, -1, &insertStatement, nil) == SQLITE_OK else {
      throw TaggingDatabaseError.prepareFailed(message: errorMessage(from: db))
    }
    sqlite3_bind_int64(insertStatement, 1, targetID)
    sqlite3_bind_int64(insertStatement, 2, sourceID)
    guard sqlite3_step(insertStatement) == SQLITE_DONE else {
      throw TaggingDatabaseError.executionFailed(
        code: sqlite3_errcode(db),
        message: errorMessage(from: db),
        sql: insertSQL
      )
    }

    let deleteSQL = "DELETE FROM image_tags WHERE tag_id = ?;"
    var deleteStatement: OpaquePointer?
    defer { sqlite3_finalize(deleteStatement) }
    guard sqlite3_prepare_v2(db, deleteSQL, -1, &deleteStatement, nil) == SQLITE_OK else {
      throw TaggingDatabaseError.prepareFailed(message: errorMessage(from: db))
    }
    sqlite3_bind_int64(deleteStatement, 1, sourceID)
    guard sqlite3_step(deleteStatement) == SQLITE_DONE else {
      throw TaggingDatabaseError.executionFailed(
        code: sqlite3_errcode(db),
        message: errorMessage(from: db),
        sql: deleteSQL
      )
    }
  }

  /// 清理和去重标签名称
  ///
  /// 预处理用户输入的标签名称，确保数据质量。
  ///
  /// 处理步骤：
  /// 1. **去除空白**：清理首尾的空格、换行等字符
  /// 2. **过滤空值**：忽略清理后为空的名称
  /// 3. **去重**：不区分大小写去重（保留首次出现的大小写形式）
  ///
  /// 去重逻辑：
  /// - 使用 lowercased() 作为重复判断的 key
  /// - 保留原始大小写形式（用户输入的格式）
  /// - 示例："Work"、"work"、"WORK" 只保留第一个
  ///
  /// 使用场景：
  /// - 用户输入标签名称时
  /// - 批量导入标签时
  /// - API 调用传入标签列表时
  ///
  /// - Parameter names: 原始标签名称数组
  /// - Returns: 清理和去重后的标签名称数组
  private func sanitizeTagNames(_ names: [String]) -> [String] {
    var result: [String] = []
    var seen: Set<String> = []
    for name in names {
      let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !trimmed.isEmpty else { continue }
      let key = trimmed.lowercased()
      if seen.insert(key).inserted {
        result.append(trimmed)
      }
    }
    return result
  }

  /// 标准化 URL 并提取文件元数据
  ///
  /// 将用户提供的 URL 转换为标准化的文件信息结构。
  ///
  /// 标准化处理：
  /// - **路径标准化**：转换为绝对路径，解析符号链接
  /// - **目录分离**：提取目录路径和文件名
  /// - **元数据提取**：获取文件标识符和安全书签
  ///
  /// 提取的元数据：
  /// 1. **path**：完整的标准化路径
  /// 2. **fileName**：文件名（用于搜索和显示）
  /// 3. **directory**：所在目录路径（用于目录统计）
  /// 4. **fileIdentifier**：文件系统标识符（用于移动追踪）
  /// 5. **bookmarkData**：安全书签（用于沙盒外访问）
  ///
  /// 为什么需要标准化：
  /// - 统一路径格式（避免 /path/ 和 /path 被视为不同路径）
  /// - 解析符号链接（确保指向同一文件）
  /// - 便于数据库去重和查询
  ///
  /// - Parameter url: 原始 URL
  /// - Returns: 标准化的 URL 信息结构
  private func normalize(url: URL) -> NormalizedURL {
    let standardized = url.standardizedFileURL
    let path = standardized.path
    let directory = standardized.deletingLastPathComponent().path
    let fileName = standardized.lastPathComponent
    let identifier = fileIdentifier(for: standardized)
    let bookmark = bookmarkData(for: standardized)
    return NormalizedURL(
      path: path,
      fileName: fileName,
      directory: directory,
      fileIdentifier: identifier,
      bookmarkData: bookmark
    )
  }

  /// 获取文件系统标识符
  ///
  /// 提取文件的持久化标识符（inode），用于追踪文件移动/重命名。
  ///
  /// 文件标识符特性：
  /// - **持久化**：文件移动或重命名后标识符不变
  /// - **唯一性**：同一卷内的每个文件有唯一标识
  /// - **跨卷失效**：文件移动到其他磁盘卷后标识符会变化
  ///
  /// 使用场景：
  /// - 用户移动图片到其他目录
  /// - 用户重命名图片文件
  /// - 文件路径变化但实体未变
  ///
  /// 失败情况：
  /// - 文件不存在
  /// - 没有读取权限
  /// - 网络文件系统（可能不支持）
  ///
  /// - Parameter url: 文件 URL
  /// - Returns: 文件标识符字符串，失败时返回 nil
  private func fileIdentifier(for url: URL) -> String? {
    guard
      let values = try? url.resourceValues(forKeys: [.fileResourceIdentifierKey]),
      let rawIdentifier = values.fileResourceIdentifier
    else {
      return nil
    }
    return String(describing: rawIdentifier)
  }

  /// 创建安全书签数据
  ///
  /// 为文件创建安全书签（Security-Scoped Bookmark），用于沙盒外文件的持久化访问。
  ///
  /// 安全书签特性：
  /// - **权限保持**：记录用户授予的访问权限
  /// - **路径追踪**：文件移动后可通过书签重新定位
  /// - **持久化**：应用重启后仍然有效
  ///
  /// 选项说明：
  /// - **minimalBookmark**：最小化书签数据，减少存储空间
  /// - **fileResourceIdentifierKey**：包含文件标识符，提高追踪能力
  ///
  /// 使用场景：
  /// - 沙盒外的文件（用户通过文件选择器选择的）
  /// - 需要在应用重启后继续访问的文件
  /// - 文件可能被移动到其他位置
  ///
  /// 注意事项：
  /// - 书签可能因系统更新或权限变化失效
  /// - 需要定期刷新以保持有效性
  /// - 沙盒内文件不需要书签
  ///
  /// - Parameter url: 文件 URL
  /// - Returns: 书签数据，创建失败时返回 nil
  private func bookmarkData(for url: URL) -> Data? {
    do {
      return try url.bookmarkData(
        options: [.minimalBookmark],
        includingResourceValuesForKeys: [.fileResourceIdentifierKey],
        relativeTo: nil
      )
    } catch {
      return nil
    }
  }

  /// 解析安全书签数据为 URL
  ///
  /// 从书签数据恢复文件访问，用于找回移动后的文件。
  ///
  /// 解析选项：
  /// - **withoutUI**：不显示用户界面（如权限请求对话框）
  /// - **withoutMounting**：不自动挂载卷（如网络驱动器）
  ///
  /// 过期检测：
  /// - isStale 标志表示书签是否过期
  /// - 过期的书签可能仍然可用，但建议重新创建
  /// - 当前实现忽略 isStale，只要能解析就使用
  ///
  /// 失败原因：
  /// - 书签数据损坏或格式错误
  /// - 文件已被永久删除
  /// - 权限已被撤销
  /// - 卷未挂载（网络驱动器）
  ///
  /// 使用场景：
  /// - 巡检时尝试恢复丢失的文件
  /// - 应用启动时验证文件可访问性
  ///
  /// - Parameter data: 安全书签数据
  /// - Returns: 解析出的 URL，失败时返回 nil
  private func resolveURL(from data: Data) -> URL? {
    var isStale = false
    guard let url = try? URL(
      resolvingBookmarkData: data,
      options: [.withoutUI, .withoutMounting],
      relativeTo: nil,
      bookmarkDataIsStale: &isStale
    ) else {
      return nil
    }
    return url
  }
}

// MARK: - Support types

private struct NormalizedURL {
  let path: String
  let fileName: String
  let directory: String
  let fileIdentifier: String?
  let bookmarkData: Data?
}

// MARK: - SQLite helpers

extension TagRepository {
  /// 获取 SQLite 错误消息
  ///
  /// 从数据库连接中提取最后一次操作的错误信息。
  ///
  /// - Parameter db: 数据库连接句柄
  /// - Returns: 错误消息字符串，无法获取时返回 "unknown"
  private func errorMessage(from db: OpaquePointer) -> String {
    guard let cString = sqlite3_errmsg(db) else { return "unknown" }
    return String(cString: cString)
  }

  /// 通过名称查询标签 ID（不区分大小写）
  ///
  /// 查询数据库中是否存在指定名称的标签。
  ///
  /// 查询特点：
  /// - 不区分大小写：LOWER() 函数统一转换为小写比较
  /// - 返回第一个匹配：LIMIT 1 确保只返回一个结果
  ///
  /// 使用场景：
  /// - 创建标签前检查是否已存在
  /// - 重命名标签时检查名称冲突
  ///
  /// - Parameters:
  ///   - db: 数据库连接句柄
  ///   - name: 标签名称
  /// - Returns: 标签 ID，未找到时返回 nil
  /// - Throws: 数据库错误
  private func queryTagID(db: OpaquePointer, name: String) throws -> Int64? {
    let sql = "SELECT id FROM tags WHERE LOWER(name) = LOWER(?) LIMIT 1;"
    var statement: OpaquePointer?
    defer { sqlite3_finalize(statement) }
    guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
      throw TaggingDatabaseError.prepareFailed(message: errorMessage(from: db))
    }
    sqlite3_bind_text(statement, 1, name, -1, SQLITE_TRANSIENT)
    if sqlite3_step(statement) == SQLITE_ROW {
      return sqlite3_column_int64(statement, 0)
    }
    return nil
  }

  /// 更新标签的时间戳
  ///
  /// 标记标签被"触碰"，刷新其 updated_at 字段。
  ///
  /// 使用场景：
  /// - 标签已存在时，更新最后使用时间
  /// - 追踪标签的活跃度
  ///
  /// - Parameters:
  ///   - db: 数据库连接句柄
  ///   - id: 标签 ID
  ///   - timestamp: 新的时间戳
  /// - Throws: 数据库错误
  private func touchTag(db: OpaquePointer, id: Int64, timestamp: TimeInterval) throws {
    let sql = "UPDATE tags SET updated_at = ? WHERE id = ?;"
    try executeUpdate(db: db, sql: sql) { statement in
      sqlite3_bind_double(statement, 1, timestamp)
      sqlite3_bind_int64(statement, 2, id)
    }
  }

  /// 执行通用的 UPDATE/DELETE 语句
  ///
  /// 封装 SQLite 语句的执行流程，减少重复代码。
  ///
  /// 执行流程：
  /// 1. 预编译 SQL 语句
  /// 2. 调用 bind 闭包绑定参数
  /// 3. 执行语句并验证结果
  /// 4. 自动释放资源（defer finalize）
  ///
  /// 适用场景：
  /// - UPDATE 语句（更新记录）
  /// - DELETE 语句（删除记录）
  /// - 其他不返回结果集的 DML 语句
  ///
  /// 不适用场景：
  /// - SELECT 语句（使用专门的查询方法）
  /// - INSERT 语句需要获取自增 ID（使用 sqlite3_last_insert_rowid）
  ///
  /// - Parameters:
  ///   - db: 数据库连接句柄
  ///   - sql: SQL 语句
  ///   - bind: 参数绑定闭包，默认为空（无参数）
  /// - Throws: 数据库错误
  private func executeUpdate(
    db: OpaquePointer,
    sql: String,
    bind: (OpaquePointer?) throws -> Void = { _ in }
  ) throws {
    var statement: OpaquePointer?
    defer { sqlite3_finalize(statement) }
    guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
      throw TaggingDatabaseError.prepareFailed(message: errorMessage(from: db))
    }
    try bind(statement)
    guard sqlite3_step(statement) == SQLITE_DONE else {
      throw TaggingDatabaseError.executionFailed(
        code: sqlite3_errcode(db),
        message: errorMessage(from: db),
        sql: sql
      )
    }
  }

  /// 清理未使用的标签
  ///
  /// 删除所有没有图片关联的孤立标签。
  ///
  /// SQL 逻辑：
  /// - NOT EXISTS 子查询：检查标签是否在 image_tags 中被引用
  /// - SELECT 1：只需要判断存在性，不需要实际数据
  ///
  /// 调用时机：
  /// - 用户手动触发清理操作
  /// - 删除图片或移除标签后自动调用
  /// - 巡检完成后清理失效标签
  ///
  /// 性能考虑：
  /// - 使用 NOT EXISTS 比 NOT IN 更高效
  /// - index on image_tags(tag_id) 加速子查询
  ///
  /// - Parameter db: 数据库连接句柄
  /// - Throws: 数据库错误
  private func cleanupUnusedTags(db: OpaquePointer) throws {
    let sql = """
      DELETE FROM tags
      WHERE NOT EXISTS (
        SELECT 1 FROM image_tags WHERE image_tags.tag_id = tags.id
      );
    """
    try executeUpdate(db: db, sql: sql)
  }

  /// 重置临时路径表
  ///
  /// 删除并重新创建临时表，用于批量查询的路径存储。
  ///
  /// 临时表特性：
  /// - **temp 数据库**：存储在内存或临时文件中
  /// - **连接隔离**：每个连接有独立的临时表空间
  /// - **自动清理**：连接断开时自动删除
  ///
  /// 表结构：
  /// - path TEXT PRIMARY KEY：图片路径，主键去重
  ///
  /// 使用目的：
  /// - 批量查询：避免构造超长的 IN (...) 子句
  /// - 性能优化：临时表可以利用索引
  /// - SQL 限制：避免达到 SQLite 的查询长度限制
  ///
  /// - Parameter db: 数据库连接句柄
  /// - Throws: 数据库错误
  private func resetTempRequestPathsTable(db: OpaquePointer) throws {
    let dropSQL = "DROP TABLE IF EXISTS temp.request_paths;"
    if sqlite3_exec(db, dropSQL, nil, nil, nil) != SQLITE_OK {
      throw TaggingDatabaseError.executionFailed(
        code: sqlite3_errcode(db),
        message: errorMessage(from: db),
        sql: dropSQL
      )
    }
    let createSQL = "CREATE TEMP TABLE request_paths (path TEXT PRIMARY KEY);"
    if sqlite3_exec(db, createSQL, nil, nil, nil) != SQLITE_OK {
      throw TaggingDatabaseError.executionFailed(
        code: sqlite3_errcode(db),
        message: errorMessage(from: db),
        sql: createSQL
      )
    }
  }

  /// 删除临时路径表
  ///
  /// 清理使用完毕的临时表，释放资源。
  ///
  /// 虽然临时表在连接断开时会自动删除，但显式删除有以下好处：
  /// - 立即释放内存或临时文件空间
  /// - 避免同一连接中多次操作的干扰
  /// - 保持代码的对称性（create/drop 配对）
  ///
  /// - Parameter db: 数据库连接句柄
  /// - Throws: 数据库错误
  private func dropTempRequestPathsTable(db: OpaquePointer) throws {
    let sql = "DROP TABLE IF EXISTS temp.request_paths;"
    if sqlite3_exec(db, sql, nil, nil, nil) != SQLITE_OK {
      throw TaggingDatabaseError.executionFailed(
        code: sqlite3_errcode(db),
        message: errorMessage(from: db),
        sql: sql
      )
    }
  }

  /// 填充临时路径表
  ///
  /// 将路径列表批量插入到临时表中，用于后续的 JOIN 查询。
  ///
  /// 执行策略：
  /// - **事务包裹**：批量 INSERT 操作在事务中执行，提高性能
  /// - **INSERT OR IGNORE**：自动去重，路径相同时忽略重复插入
  /// - **复用语句**：循环绑定参数，比多次预编译快
  ///
  /// 事务处理：
  /// - IMMEDIATE 模式：立即获取写锁，避免并发冲突
  /// - defer 回滚：发生错误时自动回滚事务
  /// - 手动提交：成功完成后提交事务
  ///
  /// 性能优化：
  /// - 事务批处理：1000 条路径约 10ms，比逐条插入快 100 倍
  /// - 复用语句：减少 SQL 解析开销
  ///
  /// - Parameters:
  ///   - db: 数据库连接句柄
  ///   - paths: 要插入的路径数组
  /// - Throws: 数据库错误
  private func populateTempRequestPathsTable(
    db: OpaquePointer,
    paths: [String]
  ) throws {
    guard !paths.isEmpty else { return }
    try beginTransaction(db, mode: "IMMEDIATE")
    var didCommit = false
    defer {
      if !didCommit {
        try? rollbackTransaction(db)
      }
    }
    let insertSQL = "INSERT OR IGNORE INTO temp.request_paths(path) VALUES (?);"
    var statement: OpaquePointer?
    defer { sqlite3_finalize(statement) }
    guard sqlite3_prepare_v2(db, insertSQL, -1, &statement, nil) == SQLITE_OK else {
      throw TaggingDatabaseError.prepareFailed(message: errorMessage(from: db))
    }
    for path in paths {
      sqlite3_reset(statement)
      sqlite3_clear_bindings(statement)
      sqlite3_bind_text(statement, 1, path, -1, SQLITE_TRANSIENT)
      guard sqlite3_step(statement) == SQLITE_DONE else {
        throw TaggingDatabaseError.executionFailed(
          code: sqlite3_errcode(db),
          message: errorMessage(from: db),
          sql: insertSQL
        )
      }
    }
    try commitTransaction(db)
    didCommit = true
  }

  /// 从查询结果中提取字符串列
  ///
  /// 安全地读取 TEXT 类型的列值，自动转换 C 字符串为 Swift String。
  ///
  /// 处理逻辑：
  /// - statement 或列值为 nil 时返回 nil
  /// - 自动处理 UTF-8 编码转换
  ///
  /// SQLite 列类型对应：
  /// - TEXT 列：返回字符串内容
  /// - NULL 列：返回 nil
  /// - 其他类型：SQLite 自动转换为字符串
  ///
  /// - Parameters:
  ///   - statement: 查询语句句柄
  ///   - index: 列索引（从 0 开始）
  /// - Returns: 列值字符串，NULL 或无效时返回 nil
  private func stringColumn(_ statement: OpaquePointer?, index: Int32) -> String? {
    guard
      let statement,
      let cString = sqlite3_column_text(statement, index)
    else { return nil }
    return String(cString: cString)
  }

  /// 从查询结果中提取二进制数据列
  ///
  /// 安全地读取 BLOB 类型的列值，转换为 Swift Data。
  ///
  /// 处理逻辑：
  /// - 获取 BLOB 数据指针和长度
  /// - 创建 Data 对象（复制数据，不是引用）
  /// - statement 或列值为 nil 时返回 nil
  ///
  /// SQLite 列类型对应：
  /// - BLOB 列：返回二进制数据
  /// - NULL 列：返回 nil
  ///
  /// 使用场景：
  /// - 读取安全书签数据
  /// - 读取图片缩略图（如果存储在数据库中）
  ///
  /// - Parameters:
  ///   - statement: 查询语句句柄
  ///   - index: 列索引（从 0 开始）
  /// - Returns: 列值数据，NULL 或无效时返回 nil
  private func dataColumn(_ statement: OpaquePointer?, index: Int32) -> Data? {
    guard
      let statement,
      let blobPointer = sqlite3_column_blob(statement, index)
    else { return nil }
    let length = Int(sqlite3_column_bytes(statement, index))
    return Data(bytes: blobPointer, count: length)
  }

  /// 绑定二进制数据到 SQL 参数
  ///
  /// 将 Swift Data 绑定到 SQL 语句的 BLOB 参数。
  ///
  /// 处理逻辑：
  /// - data 为 nil：绑定 NULL
  /// - data 有值：绑定 BLOB 数据
  /// - SQLITE_TRANSIENT：告诉 SQLite 复制数据（不持有指针）
  ///
  /// SQLITE_TRANSIENT 说明：
  /// - 值为 -1，表示"临时的"
  /// - SQLite 会立即复制数据，不会引用原始指针
  /// - 避免数据在执行时被释放导致的内存问题
  ///
  /// 使用场景：
  /// - 插入/更新安全书签数据
  /// - 存储任意二进制数据到数据库
  ///
  /// - Parameters:
  ///   - data: 要绑定的数据（可选）
  ///   - statement: SQL 语句句柄
  ///   - index: 参数索引（从 1 开始）
  private func bindBlob(_ data: Data?, statement: OpaquePointer?, index: Int32) {
    guard let statement else { return }
    guard let data else {
      sqlite3_bind_null(statement, index)
      return
    }
    _ = data.withUnsafeBytes { buffer in
      sqlite3_bind_blob(statement, index, buffer.baseAddress, Int32(buffer.count), SQLITE_TRANSIENT)
    }
  }

  /// 开始数据库事务
  ///
  /// 启动事务，将后续操作包装在一个原子单元中。
  ///
  /// 事务模式：
  /// - **DEFERRED**（默认）：延迟加锁，首次读取时加读锁，首次写入时加写锁
  /// - **IMMEDIATE**：立即加写锁，适合确定会写入的场景，避免锁升级失败
  /// - **EXCLUSIVE**：立即加排他锁，阻止所有其他连接（很少使用）
  ///
  /// 使用 IMMEDIATE 的场景：
  /// - 批量写入操作（避免其他连接抢占写锁）
  /// - 复杂的读-写操作（确保一致性）
  ///
  /// 注意事项：
  /// - 事务必须配对 commit 或 rollback
  /// - 未提交的事务会持有锁，影响并发
  /// - 使用 defer 确保异常时回滚
  ///
  /// - Parameters:
  ///   - db: 数据库连接句柄
  ///   - mode: 事务模式（DEFERRED/IMMEDIATE/EXCLUSIVE）
  /// - Throws: 数据库错误
  private func beginTransaction(_ db: OpaquePointer, mode: String = "DEFERRED") throws {
    let sql = "BEGIN \(mode);"
    guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else {
      throw TaggingDatabaseError.executionFailed(
        code: sqlite3_errcode(db),
        message: errorMessage(from: db),
        sql: sql
      )
    }
  }

  /// 提交事务
  ///
  /// 将事务中的所有修改持久化到数据库。
  ///
  /// 提交语义：
  /// - 所有修改一次性写入
  /// - 释放持有的锁
  /// - 对其他连接可见
  ///
  /// 失败情况（极少见）：
  /// - 磁盘空间不足
  /// - 文件系统错误
  /// - 约束检查延迟到提交时才失败
  ///
  /// - Parameter db: 数据库连接句柄
  /// - Throws: 数据库错误
  private func commitTransaction(_ db: OpaquePointer) throws {
    let sql = "COMMIT;"
    guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else {
      throw TaggingDatabaseError.executionFailed(
        code: sqlite3_errcode(db),
        message: errorMessage(from: db),
        sql: sql
      )
    }
  }

  /// 回滚事务
  ///
  /// 撤销事务中的所有修改，恢复到事务开始前的状态。
  ///
  /// 回滚特点：
  /// - 所有修改被丢弃
  /// - 数据库恢复到事务前的状态
  /// - 立即释放锁
  ///
  /// 使用场景：
  /// - 操作失败时撤销部分修改
  /// - defer 块中的异常清理
  /// - 用户取消操作
  ///
  /// 注意事项：
  /// - 回滚不会失败，忽略返回值
  /// - 通常在 defer 或 catch 块中调用
  ///
  /// - Parameter db: 数据库连接句柄
  /// - Throws: 不抛出异常（回滚总是成功）
  private func rollbackTransaction(_ db: OpaquePointer) throws {
    _ = sqlite3_exec(db, "ROLLBACK;", nil, nil, nil)
  }
}

enum TagRepositoryError: LocalizedError {
  case duplicateName
  case invalidName

  var errorDescription: String? {
    switch self {
    case .duplicateName:
      return L10n.string("tag_error_duplicate")
    case .invalidName:
      return L10n.string("tag_error_invalid_name")
    }
  }
}
