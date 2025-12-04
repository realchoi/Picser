//
//  BatchDeletionConfirmationSheet.swift
//
//  批量删除确认对话框
//  显示待删除图片的预览、文件列表和删除选项，支持进度显示和失败重试
//

import SwiftUI

/// 批量删除确认对话框
///
/// 显示详细的删除确认信息，包括缩略图预览、文件列表、删除选项等。
///
/// 核心功能：
/// 1. **缩略图预览**：显示前 6 张图片的缩略图网格
/// 2. **文件列表**：可滚动的完整文件列表，显示文件名和大小
/// 3. **删除模式选择**：移到废纸篓 / 永久删除
/// 4. **智能选项**：可选择同时删除孤立标签
/// 5. **进度显示**：删除过程中显示进度条和当前进度
/// 6. **失败处理**：显示失败文件列表，支持重试
/// 7. **数量限制**：超过阈值时显示二次确认
///
/// 使用场景：
/// - 用户通过标签筛选后批量删除图片
/// - 显示详细信息避免误删
struct BatchDeletionConfirmationSheet: View {
  @Environment(\.dismiss) private var dismiss

  /// 待删除的图片 URL 列表
  let urls: [URL]

  /// 删除确认回调
  /// - Parameters:
  ///   - mode: 删除模式（废纸篓/永久删除）
  ///   - removeOrphanTags: 是否同时删除孤立标签
  let onConfirm: (ContentView.ImageDeletionMode, Bool) async -> Void

  /// 获取删除进度（0.0 - 1.0）
  let getProgress: () -> Double

  /// 是否正在执行删除
  let isDeleting: () -> Bool

  /// 获取失败的文件列表
  let getFailedURLs: () -> [(URL, Error)]

  /// 即将变成孤立的标签名称列表
  let orphanTagNames: [String]

  // MARK: - 视图状态

  /// 选中的删除模式
  @State private var selectedMode: ContentView.ImageDeletionMode = .moveToTrash

  /// 是否删除孤立标签
  @State private var removeOrphanTags = false

  /// 是否展开显示所有文件
  @State private var showAllFiles = false

  /// 是否显示二次确认（数量超过阈值）
  @State private var showingSecondaryConfirmation = false

  /// 是否显示失败列表
  @State private var showingFailureList = false

  /// 缩略图当前显示的数量
  @State private var thumbnailDisplayCount = 6

  // MARK: - 常量配置

  /// 缩略图每次加载数量
  private let previewLimit = 6

  /// 文件列表默认显示数量
  private let fileListLimit = 10

  /// 需要二次确认的数量阈值
  private let secondaryConfirmationThreshold = 100

  // MARK: - 主视图

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      if isDeleting() {
        // 删除进行中：显示进度视图
        deletionProgressView
      } else if !getFailedURLs().isEmpty {
        // 删除完成但有失败：显示失败列表
        failureView
      } else {
        // 初始确认视图
        confirmationView
      }
    }
    .frame(width: 650)
  }

  // MARK: - 确认视图

  private var confirmationView: some View {
    VStack(alignment: .leading, spacing: 0) {
      // 标题区域
      headerView
        .padding()

      Divider()

      // 内容区域（可滚动）
      ScrollView {
        VStack(alignment: .leading, spacing: 20) {
          // 缩略图网格
          thumbnailGrid
            .padding(.top, 16)

          // 统计信息
          statisticsView

          // 文件列表
          fileListSection
        }
        .padding(.horizontal)
        .padding(.bottom, 16)
      }
      .frame(maxHeight: 400)

      Divider()

      // 选项区域
      optionsSection
        .padding()

      Divider()

      // 按钮区域
      buttonsRow
        .padding()
    }
    .confirmationDialog(
      L10n.string("batch_delete_secondary_confirmation_title"),
      isPresented: $showingSecondaryConfirmation
    ) {
      Button(L10n.string("batch_delete_confirm_large_button"), role: .destructive) {
        performDeletion()
      }
      Button(L10n.key("cancel_button"), role: .cancel) {}
    } message: {
      Text(
        String(
          format: L10n.string("batch_delete_secondary_confirmation_message"),
          urls.count
        )
      )
    }
  }

  // MARK: - 标题视图

  private var headerView: some View {
    HStack(spacing: 12) {
      Image(systemName: "exclamationmark.triangle.fill")
        .font(.title2)
        .foregroundColor(.orange)

      VStack(alignment: .leading, spacing: 4) {
        Text(String(format: L10n.string("batch_delete_title"), urls.count))
          .font(.headline)
        Text(totalSizeText)
          .font(.caption)
          .foregroundColor(.secondary)
      }

      Spacer()
    }
  }

  // MARK: - 缩略图网格

  private var thumbnailGrid: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(L10n.string("batch_delete_preview_title"))
        .font(.subheadline)
        .fontWeight(.medium)

      LazyVGrid(
        columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3),
        spacing: 8
      ) {
        let displayCount = min(thumbnailDisplayCount, urls.count)
        let displayedURLs = Array(urls.prefix(displayCount))

        ForEach(Array(displayedURLs.enumerated()), id: \.offset) { _, url in
          AsyncImage(url: url) { image in
            image
              .resizable()
              .aspectRatio(contentMode: .fill)
          } placeholder: {
            ZStack {
              Color.gray.opacity(0.2)
              ProgressView()
                .scaleEffect(0.8)
            }
          }
          .frame(width: 180, height: 120)
          .clipShape(RoundedRectangle(cornerRadius: 8))
          .overlay(
            RoundedRectangle(cornerRadius: 8)
              .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
          )
        }
      }

      HStack(spacing: 16) {
        if thumbnailDisplayCount < urls.count {
          let remainingCount = urls.count - thumbnailDisplayCount
          Button {
            withAnimation {
              thumbnailDisplayCount = min(thumbnailDisplayCount + previewLimit, urls.count)
            }
          } label: {
            Text(String(format: L10n.string("batch_delete_more_images"), remainingCount))
              .font(.caption)
              .foregroundColor(.accentColor)
          }
          .buttonStyle(.plain)
        }

        if thumbnailDisplayCount > previewLimit {
          Button {
            withAnimation {
              thumbnailDisplayCount = previewLimit
            }
          } label: {
            Text(L10n.string("batch_delete_show_less"))
              .font(.caption)
              .foregroundColor(.accentColor)
          }
          .buttonStyle(.plain)
        }
      }
      .padding(.top, 4)
    }
  }

  // MARK: - 统计信息

  private var statisticsView: some View {
    HStack(spacing: 24) {
      statisticItem(
        icon: "photo.on.rectangle.angled",
        label: L10n.string("batch_delete_stat_count"),
        value: "\(urls.count)"
      )

      statisticItem(
        icon: "internaldrive",
        label: L10n.string("batch_delete_stat_size"),
        value: totalSizeText
      )
    }
    .padding(.vertical, 12)
    .padding(.horizontal, 16)
    .background(
      RoundedRectangle(cornerRadius: 8, style: .continuous)
        .fill(Color.secondary.opacity(0.08))
    )
  }

  private func statisticItem(icon: String, label: String, value: String) -> some View {
    HStack(spacing: 8) {
      Image(systemName: icon)
        .foregroundColor(.secondary)
      VStack(alignment: .leading, spacing: 2) {
        Text(label)
          .font(.caption)
          .foregroundColor(.secondary)
        Text(value)
          .font(.body)
          .fontWeight(.medium)
      }
    }
  }

  // MARK: - 文件列表

  private var fileListSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Text(L10n.string("batch_delete_file_list_title"))
          .font(.subheadline)
          .fontWeight(.medium)

        Spacer()

        if urls.count > fileListLimit {
          Button {
            showAllFiles.toggle()
          } label: {
            Text(
              showAllFiles
                ? L10n.string("batch_delete_show_less")
                : String(format: L10n.string("batch_delete_show_all"), urls.count)
            )
            .font(.caption)
          }
          .buttonStyle(.plain)
        }
      }

      VStack(alignment: .leading, spacing: 4) {
        let displayedURLs = showAllFiles ? urls : Array(urls.prefix(fileListLimit))
        ForEach(Array(displayedURLs.enumerated()), id: \.offset) { _, url in
          fileListRow(url: url)
        }
      }
      .padding(8)
      .background(
        RoundedRectangle(cornerRadius: 6, style: .continuous)
          .fill(Color.secondary.opacity(0.05))
      )
    }
  }

  private func fileListRow(url: URL) -> some View {
    HStack(spacing: 8) {
      Image(systemName: "photo")
        .font(.caption)
        .foregroundColor(.secondary)
        .frame(width: 16)

      Text(url.lastPathComponent)
        .font(.caption)
        .lineLimit(1)

      Spacer()

      if let size = fileSize(at: url) {
        Text(size)
          .font(.caption)
          .foregroundColor(.secondary)
      }
    }
    .padding(.vertical, 2)
  }

  // MARK: - 选项区域

  private var optionsSection: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text(L10n.string("batch_delete_options_title"))
        .font(.subheadline)
        .fontWeight(.medium)

      // 删除模式选择
      Picker(L10n.string("batch_delete_mode_label"), selection: $selectedMode) {
        Text(L10n.string("batch_delete_mode_trash"))
          .tag(ContentView.ImageDeletionMode.moveToTrash)
        Text(L10n.string("batch_delete_mode_permanent"))
          .tag(ContentView.ImageDeletionMode.deletePermanently)
      }
      .pickerStyle(.radioGroup)

      // 删除孤立标签选项
      VStack(alignment: .leading, spacing: 6) {
        Toggle(
          L10n.string("batch_delete_option_remove_orphan_tags"),
          isOn: $removeOrphanTags
        )
        .toggleStyle(.checkbox)

        // 显示即将删除的孤立标签名称
        if !orphanTagNames.isEmpty {
          let displayedNames = orphanTagNames.prefix(5).joined(separator: ", ")
          let remaining = orphanTagNames.count - 5
          HStack(alignment: .top, spacing: 6) {
            Image(systemName: "tag.fill")
              .font(.caption)
              .foregroundColor(.secondary)
            if remaining > 0 {
              Text(String(
                format: L10n.string("batch_delete_orphan_tags_more"),
                displayedNames,
                remaining
              ))
              .font(.caption)
              .foregroundColor(.secondary)
            } else {
              Text(String(
                format: L10n.string("batch_delete_orphan_tags"),
                displayedNames
              ))
              .font(.caption)
              .foregroundColor(.secondary)
            }
          }
          .padding(.leading, 20)
        }
      }

      // 警告提示
      HStack(spacing: 8) {
        Image(systemName: "exclamationmark.circle.fill")
          .foregroundColor(.orange)
        Text(
          selectedMode == .moveToTrash
            ? L10n.string("batch_delete_warning_trash")
            : L10n.string("batch_delete_warning_permanent")
        )
        .font(.caption)
        .foregroundColor(.secondary)
      }
      .padding(8)
      .background(
        RoundedRectangle(cornerRadius: 6, style: .continuous)
          .fill(Color.orange.opacity(0.1))
      )
    }
  }

  // MARK: - 按钮区域

  private var buttonsRow: some View {
    HStack {
      Button(L10n.key("cancel_button")) {
        dismiss()
      }
      .keyboardShortcut(.cancelAction)

      Spacer()

      Button {
        if urls.count >= secondaryConfirmationThreshold {
          showingSecondaryConfirmation = true
        } else {
          performDeletion()
        }
      } label: {
        Text(
          selectedMode == .moveToTrash
            ? L10n.string("batch_delete_confirm_trash")
            : L10n.string("batch_delete_confirm_permanent")
        )
      }
      .buttonStyle(.borderedProminent)
      .tint(selectedMode == .deletePermanently ? .red : .accentColor)
      .keyboardShortcut(.defaultAction)
    }
  }

  // MARK: - 删除进度视图

  private var deletionProgressView: some View {
    VStack(spacing: 24) {
      Spacer()

      // 进度图标
      ZStack {
        Circle()
          .stroke(Color.secondary.opacity(0.2), lineWidth: 8)
          .frame(width: 80, height: 80)

        Circle()
          .trim(from: 0, to: getProgress())
          .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 8, lineCap: .round))
          .frame(width: 80, height: 80)
          .rotationEffect(.degrees(-90))
          .animation(.linear(duration: 0.3), value: getProgress())

        Image(systemName: "trash.fill")
          .font(.title)
          .foregroundColor(.accentColor)
      }

      // 进度文本
      VStack(spacing: 8) {
        Text(L10n.string("batch_delete_progress_title"))
          .font(.headline)

        let current = Int(getProgress() * Double(urls.count))
        Text(String(format: L10n.string("batch_delete_progress_detail"), current, urls.count))
          .font(.subheadline)
          .foregroundColor(.secondary)

        Text(String(format: "%.0f%%", getProgress() * 100))
          .font(.title2)
          .fontWeight(.bold)
          .foregroundColor(.accentColor)
      }

      Spacer()
    }
    .frame(height: 400)
    .padding()
  }

  // MARK: - 失败视图

  private var failureView: some View {
    VStack(alignment: .leading, spacing: 0) {
      // 失败标题
      HStack(spacing: 12) {
        Image(systemName: "exclamationmark.triangle.fill")
          .font(.title2)
          .foregroundColor(.red)

        VStack(alignment: .leading, spacing: 4) {
          let failedCount = getFailedURLs().count
          let successCount = urls.count - failedCount
          Text(String(format: L10n.string("batch_delete_partial_success"), successCount, failedCount))
            .font(.headline)
          Text(L10n.string("batch_delete_failure_subtitle"))
            .font(.caption)
            .foregroundColor(.secondary)
        }

        Spacer()
      }
      .padding()

      Divider()

      // 失败文件列表
      ScrollView {
        VStack(alignment: .leading, spacing: 8) {
          ForEach(Array(getFailedURLs().enumerated()), id: \.offset) { _, item in
            failureRow(url: item.0, error: item.1)
          }
        }
        .padding()
      }
      .frame(maxHeight: 300)

      Divider()

      // 失败操作按钮
      HStack {
        Button(L10n.string("batch_delete_failure_close")) {
          dismiss()
        }

        Spacer()

        Button(L10n.string("batch_delete_failure_retry")) {
          // TODO: 实现重试逻辑
          showingFailureList = false
          performDeletion()
        }
        .buttonStyle(.borderedProminent)
      }
      .padding()
    }
  }

  private func failureRow(url: URL, error: Error) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack(spacing: 8) {
        Image(systemName: "xmark.circle.fill")
          .foregroundColor(.red)
          .font(.caption)

        Text(url.lastPathComponent)
          .font(.body)
          .lineLimit(1)

        Spacer()
      }

      Text(error.localizedDescription)
        .font(.caption)
        .foregroundColor(.secondary)
        .padding(.leading, 24)
    }
    .padding(8)
    .background(
      RoundedRectangle(cornerRadius: 6, style: .continuous)
        .fill(Color.red.opacity(0.05))
    )
  }

  // MARK: - 辅助方法

  /// 计算总文件大小
  private var totalSizeText: String {
    let totalBytes: Int64 = urls.reduce(0) { sum, url in
      if let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
        let size = attributes[.size] as? Int64
      {
        return sum + size
      }
      return sum
    }
    return ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file)
  }

  /// 获取单个文件大小
  private func fileSize(at url: URL) -> String? {
    if let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
      let size = attributes[.size] as? Int64
    {
      return ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }
    return nil
  }

  /// 执行删除操作
  private func performDeletion() {
    Task {
      await onConfirm(selectedMode, removeOrphanTags)
    }
  }
}
