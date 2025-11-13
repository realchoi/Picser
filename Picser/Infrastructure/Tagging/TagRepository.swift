//
//  TagRepository.swift
//
//  Created by Eric Cai on 2025/11/08.
//

import Foundation
import SQLite3

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

/// 负责提供标签读写接口，所有数据库操作都串行执行以确保线程安全
actor TagRepository {
  static let shared = TagRepository()

  private let database: TaggingDatabase

  init(database: TaggingDatabase = .shared) {
    self.database = database
  }

  // MARK: - 查询

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

  func fetchTags(forImageAt path: String) async throws -> [TagRecord] {
    try await fetchAssignments(for: [path])[path] ?? []
  }

  func fetchAssignments(for paths: [String]) async throws -> [String: [TagRecord]] {
    guard !paths.isEmpty else { return [:] }
    let distinctPaths = Array(Set(paths))
    return try await database.perform { db in
      try resetTempRequestPathsTable(db: db)
      defer { try? dropTempRequestPathsTable(db: db) }
      try populateTempRequestPathsTable(db: db, paths: distinctPaths)
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
      var grouped: [String: [TagRecord]] = [:]
      while sqlite3_step(statement) == SQLITE_ROW {
        guard let path = stringColumn(statement, index: 0) else { continue }
        let record = TagRecord(
          id: sqlite3_column_int64(statement, 1),
          name: stringColumn(statement, index: 2) ?? "",
          colorHex: stringColumn(statement, index: 3),
          usageCount: 0,
          createdAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 4)),
          updatedAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 5))
        )
        grouped[path, default: []].append(record)
      }
      return grouped
    }
  }

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

  func assign(tagNames: [String], to url: URL) async throws -> [TagRecord] {
    let result = try await assign(tagNames: tagNames, to: [url])
    return result[url.standardizedFileURL.path] ?? []
  }

  func assign(tagNames: [String], to urls: [URL]) async throws -> [String: [TagRecord]] {
    guard !urls.isEmpty else { return [:] }
    let normalizedMap = Dictionary(uniqueKeysWithValues: urls.map { url in
      let normalized = normalize(url: url)
      return (normalized.path, normalized)
    })
    guard !normalizedMap.isEmpty else { return [:] }

    let preparedNames = sanitizeTagNames(tagNames)
    if preparedNames.isEmpty {
      return try await database.perform { db in
        var result: [String: [TagRecord]] = [:]
        let now = Date().timeIntervalSince1970
        for normalized in normalizedMap.values {
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

    return try await database.perform { db in
      let now = Date().timeIntervalSince1970
      try beginTransaction(db, mode: "IMMEDIATE")
      do {
        let tagIDs = try ensureTags(db: db, names: preparedNames, timestamp: now)
        var output: [String: [TagRecord]] = [:]
        for normalized in normalizedMap.values {
          guard let imageID = try resolveImageID(
            db: db,
            normalized: normalized,
            timestamp: now,
            allowCreate: true
          ) else { continue }
          try bindTags(db: db, imageID: imageID, tagIDs: tagIDs, timestamp: now)
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
        for source in sources {
          try migrateAssignments(db: db, from: source, to: targetID, timestamp: timestamp)
        }
        try deleteTags(db: db, ids: Array(sources))
        try commitTransaction(db)
        return targetID
      } catch {
        try rollbackTransaction(db)
        throw error
      }
    }
  }

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
        try executeUpdate(
          db: db,
          sql: "DELETE FROM image_tags WHERE image_id = ? AND tag_id = ?;"
        ) { statement in
          sqlite3_bind_int64(statement, 1, imageID)
          sqlite3_bind_int64(statement, 2, tagID)
        }
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

  func rename(tagID: Int64, newName: String) async throws {
    let sanitized = newName.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !sanitized.isEmpty else { throw TagRepositoryError.invalidName }
    try await database.perform { db in
      try beginTransaction(db, mode: "IMMEDIATE")
      do {
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

  func purgeUnusedTags() async throws {
    try await database.perform { db in
      try cleanupUnusedTags(db: db)
    }
  }

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
        try cleanupUnusedTags(db: db)
        try commitTransaction(db)
      } catch {
        try rollbackTransaction(db)
        throw error
      }
    }
  }

  /// 根据文件真实位置刷新数据库中记录的路径信息
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

  /// 巡检数据库中记录的图片路径，尝试自动修复或回收失效数据
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

  func deleteTags(_ tagIDs: [Int64]) async throws {
    let unique = Array(Set(tagIDs))
    guard !unique.isEmpty else { return }
    try await database.perform { db in
      try deleteTags(db: db, ids: unique)
    }
  }

  // MARK: - Private helpers

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

  private func fileIdentifier(for url: URL) -> String? {
    guard
      let values = try? url.resourceValues(forKeys: [.fileResourceIdentifierKey]),
      let rawIdentifier = values.fileResourceIdentifier
    else {
      return nil
    }
    return String(describing: rawIdentifier)
  }

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
  private func errorMessage(from db: OpaquePointer) -> String {
    guard let cString = sqlite3_errmsg(db) else { return "unknown" }
    return String(cString: cString)
  }

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

  private func touchTag(db: OpaquePointer, id: Int64, timestamp: TimeInterval) throws {
    let sql = "UPDATE tags SET updated_at = ? WHERE id = ?;"
    try executeUpdate(db: db, sql: sql) { statement in
      sqlite3_bind_double(statement, 1, timestamp)
      sqlite3_bind_int64(statement, 2, id)
    }
  }

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

  private func cleanupUnusedTags(db: OpaquePointer) throws {
    let sql = """
      DELETE FROM tags
      WHERE NOT EXISTS (
        SELECT 1 FROM image_tags WHERE image_tags.tag_id = tags.id
      );
    """
    try executeUpdate(db: db, sql: sql)
  }

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

  private func stringColumn(_ statement: OpaquePointer?, index: Int32) -> String? {
    guard
      let statement,
      let cString = sqlite3_column_text(statement, index)
    else { return nil }
    return String(cString: cString)
  }

  private func dataColumn(_ statement: OpaquePointer?, index: Int32) -> Data? {
    guard
      let statement,
      let blobPointer = sqlite3_column_blob(statement, index)
    else { return nil }
    let length = Int(sqlite3_column_bytes(statement, index))
    return Data(bytes: blobPointer, count: length)
  }

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
