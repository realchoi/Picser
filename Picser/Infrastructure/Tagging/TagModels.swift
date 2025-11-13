//
//  TagModels.swift
//
//  Created by Eric Cai on 2025/11/08.
//

import Foundation

/// 标签记录
///
/// 表示一个完整的标签对象，包含数据库持久化数据和使用统计。
/// 用于 UI 展示、筛选、推荐等各种场景。
///
/// 数据来源：从 `tags` 表查询，并 JOIN `image_tags` 表计算使用次数
struct TagRecord: Identifiable, Hashable {
  /// 数据库主键，全局唯一
  let id: Int64

  /// 标签名称，用户可编辑
  var name: String

  /// 标签颜色（可选），格式为 #RRGGBB
  /// 用于 UI 展示和颜色筛选
  var colorHex: String?

  /// 使用次数统计（有多少张图片使用了这个标签）
  /// 用于排序和推荐权重计算
  var usageCount: Int

  /// 创建时间
  var createdAt: Date

  /// 最后更新时间
  var updatedAt: Date
}

/// 作用域标签统计
///
/// 表示在当前选中的图片集合（作用域）内，某个标签的使用情况。
/// 与 TagRecord 的区别：
/// - TagRecord.usageCount：全局统计（所有图片）
/// - ScopedTagSummary.usageCount：局部统计（当前选中的图片）
///
/// 使用场景：
/// - 标签筛选面板显示当前作用域内的可用标签
/// - 推荐引擎根据作用域热度推荐标签
/// - 智能筛选器只显示作用域内相关的标签
struct ScopedTagSummary: Identifiable, Hashable {
  /// 标签 ID，对应 TagRecord.id
  let id: Int64

  /// 标签名称
  var name: String

  /// 标签颜色（可选）
  var colorHex: String?

  /// 在当前作用域内的使用次数
  /// 例如：如果选中了 10 张图片，其中 3 张使用了这个标签，则 usageCount = 3
  var usageCount: Int
}

/// 图片记录
///
/// 在数据库中跟踪图片文件的元数据，用于建立图片与标签的多对多关系。
/// 每个图片文件在 `images` 表中有一条记录，通过 `image_tags` 中间表关联到多个标签。
///
/// 设计要点：
/// - path：文件的完整路径，作为唯一标识
/// - fileIdentifier：macOS 文件系统的持久化标识，用于文件移动后的追踪
/// - bookmarkData：沙盒外文件的安全书签，保持访问权限
struct TaggedImageRecord: Identifiable, Hashable {
  /// 数据库主键
  let id: Int64

  /// 图片文件的完整路径（标准化后的绝对路径）
  /// 作为业务唯一键，用于查询和去重
  let path: String

  /// 文件名（不含路径）
  /// 用于搜索和显示
  let fileName: String

  /// 所在目录的完整路径
  /// 用于目录级别的统计和推荐
  let directory: String

  /// 记录创建时间
  var createdAt: Date

  /// 记录更新时间（图片被重新标记时更新）
  var updatedAt: Date

  /// macOS 文件唯一标识（inode）
  /// 用于跟踪文件移动、重命名等操作，保持标签关联
  var fileIdentifier: String?

  /// 安全书签数据（Security-Scoped Bookmark）
  /// 用于在应用重启后重新访问沙盒外的文件
  /// 只有沙盒外文件需要存储此数据
  var bookmarkData: Data?
}

/// 标签筛选模式
///
/// 定义多个标签组合时的匹配逻辑。
/// 使用 String 作为 RawValue 便于持久化和调试。
enum TagFilterMode: String, Codable, CaseIterable, Hashable {
  /// 任意匹配（OR 逻辑）
  /// 图片至少包含一个指定标签即可显示
  /// 例如：选中标签 A、B、C，图片只要有其中之一就显示
  case any

  /// 全部匹配（AND 逻辑）
  /// 图片必须同时包含所有指定标签才显示
  /// 例如：选中标签 A、B、C，图片必须同时有 A、B、C 三个标签
  case all

  /// 排除匹配（NOT 逻辑）
  /// 图片不能包含任何指定标签
  /// 例如：选中标签 A、B、C，只显示没有 A、B、C 的图片
  case exclude
}

/// 标签筛选条件
///
/// 综合的筛选配置，支持多维度组合筛选：
/// 1. **标签筛选**：按标签 ID 筛选（支持 any/all/exclude 模式）
/// 2. **关键词筛选**：按文件名或目录名搜索
/// 3. **颜色筛选**：按标签颜色筛选
///
/// 多个维度之间是 AND 关系，即必须同时满足所有激活的筛选条件。
///
/// 实现 Codable 以支持：
/// - 持久化到 UserDefaults（智能筛选器）
/// - 通过 URL Scheme 或 Deep Link 传递筛选条件
struct TagFilter: Equatable, Codable, Hashable {
  /// 标签匹配模式：any（任意）/ all（全部）/ exclude（排除）
  var mode: TagFilterMode

  /// 参与筛选的标签 ID 集合
  /// 空集合表示不按标签筛选
  var tagIDs: Set<Int64>

  /// 文件名/目录名关键字
  /// 空字符串或纯空白字符表示不按关键词筛选
  /// 搜索逻辑：不区分大小写的包含匹配
  var keyword: String

  /// 需要匹配的标签颜色集合
  /// 格式为 #RRGGBB（大小写不敏感）
  /// 空集合表示不按颜色筛选
  var colorHexes: Set<String>

  /// 初始化筛选条件
  ///
  /// 默认值表示"不筛选"状态，显示所有图片
  init(
    mode: TagFilterMode = .any,
    tagIDs: Set<Int64> = [],
    keyword: String = "",
    colorHexes: Set<String> = []
  ) {
    self.mode = mode
    self.tagIDs = tagIDs
    self.keyword = keyword
    self.colorHexes = colorHexes
  }

  /// 筛选器是否激活
  ///
  /// 只要有任意一个筛选条件非空，就视为激活状态。
  /// 用于优化：未激活时可以跳过筛选逻辑，直接返回所有图片。
  ///
  /// - Returns: true 表示至少有一个筛选条件生效
  var isActive: Bool {
    let hasKeyword = !keyword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    return !tagIDs.isEmpty || hasKeyword || !colorHexes.isEmpty
  }
}

/// 智能筛选器
///
/// 用户自定义的命名筛选器快照，保存常用的筛选条件组合。
/// 类似浏览器的书签，方便快速切换到特定的筛选状态。
///
/// 使用场景：
/// - 保存"工作相关"的图片筛选（标签：工作 + 项目A）
/// - 保存"待处理"的图片筛选（标签：未整理，排除模式：已归档）
/// - 保存"红色标签"的图片筛选（颜色：#FF0000）
///
/// 持久化：通过 TagSmartFilterStore 存储到 UserDefaults
struct TagSmartFilter: Identifiable, Codable, Equatable {
  /// 唯一标识符，用于编辑、删除等操作
  let id: UUID

  /// 筛选器名称，用户自定义
  /// 显示在智能筛选器列表中
  var name: String

  /// 保存的筛选条件
  /// 应用此智能筛选器时，会将此条件设置为当前激活的筛选条件
  var filter: TagFilter

  /// 初始化智能筛选器
  ///
  /// - Parameters:
  ///   - id: 唯一标识符，默认自动生成
  ///   - name: 筛选器名称
  ///   - filter: 筛选条件
  init(id: UUID = UUID(), name: String, filter: TagFilter) {
    self.id = id
    self.name = name
    self.filter = filter
  }
}

/// 标签巡检结果
///
/// 记录数据库完整性检查的结果，用于在设置页面展示统计信息。
/// 巡检过程会验证：
/// 1. 数据库中记录的图片文件是否仍然存在
/// 2. 是否可以通过安全书签重新访问文件
/// 3. 无法访问的记录会被标记为缺失
///
/// 实现 Sendable 以支持跨 actor 传递（从 TagRepository 到 MainActor）
struct TagInspectionSummary: Sendable, Equatable {
  /// 检查的图片记录总数
  let checkedCount: Int

  /// 通过安全书签成功恢复访问的记录数
  /// 适用于文件移动后，通过书签重新定位到新位置
  let recoveredCount: Int

  /// 从数据库中移除的无效记录数
  /// 文件不存在且无法恢复时，清理对应的标签关联
  let removedCount: Int

  /// 缺失文件的路径列表
  /// 用于在 UI 中显示详细信息，帮助用户定位问题
  let missingPaths: [String]

  /// 空结果，表示未执行巡检或巡检未发现问题
  static let empty = TagInspectionSummary(
    checkedCount: 0,
    recoveredCount: 0,
    removedCount: 0,
    missingPaths: []
  )
}
