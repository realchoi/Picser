//
//  CacheSettingsView.swift
//
//  Created by Eric Cai on 2025/8/22.
//

import AppKit
import SwiftUI

struct CacheSettingsView: View {
  @State private var cacheSize: Int64 = 0
  @State private var bookmarkCount: Int = 0
  @State private var bookmarkSize: Int64 = 0
  @State private var isLoading = false
  @State private var showingClearConfirmation = false
  @State private var showingClearBookmarksConfirmation = false
  @State private var refreshTask: Task<Void, Never>? = nil
  @State private var refreshGeneration: UInt = 0
  @Environment(\.isSettingsMeasurement) private var isMeasurement

  var body: some View {
    let baseView = contentView
      .settingsContentContainer()
      .onAppear {
        if !isMeasurement {
          refreshCacheSize()
        }
      }
      .onDisappear {
        refreshTask?.cancel()
        refreshTask = nil
        isLoading = false
      }

    return Group {
      if isMeasurement {
        baseView
      } else {
        baseView
          .alert(
            L10n.key("clear_cache_alert_title"),
            isPresented: $showingClearConfirmation
          ) {
            Button(L10n.key("cancel_button"), role: .cancel) {}
            Button(L10n.key("clear_button"), role: .destructive) {
              Task {
                await clearCache()
              }
            }
          } message: {
            Text(l10n: "clear_cache_alert_message")
          }
          .alert(
            L10n.key("clear_bookmarks_alert_title"),
            isPresented: $showingClearBookmarksConfirmation
          ) {
            Button(L10n.key("cancel_button"), role: .cancel) {}
            Button(L10n.key("clear_button"), role: .destructive) {
              clearBookmarks()
            }
          } message: {
            Text(l10n: "clear_bookmarks_alert_message")
          }
      }
    }
  }

  // MARK: - Private Methods

  @ViewBuilder
  private var contentView: some View {
    VStack(alignment: .leading, spacing: 20) {
      Text(l10n: "cache_settings_title")
        .font(.title2)
        .fontWeight(.semibold)

      Divider()

      // 缓存信息显示
      VStack(alignment: .leading, spacing: 16) {
        Text(l10n: "cache_info_group")
          .fontWeight(.medium)

        // 图片缓存大小
        HStack {
          Text(l10n: "cache_size_label")
            .frame(width: 120, alignment: .leading)

          ZStack {
            if isLoading {
              ProgressView()
                .scaleEffect(0.8)
            } else {
              Text(FormatUtils.fileSizeString(cacheSize))
                .font(.system(.body, design: .monospaced))
            }
          }
          .frame(width: 80, height: 20, alignment: .leading)

          Button(action: refreshCacheSize) {
            Image(systemName: "arrow.clockwise")
              .font(.caption)
          }
          .buttonStyle(.borderless)
          .help(L10n.key("refresh_cache_size"))
        }

        Text(l10n: "cache_size_description")
          .font(.caption)
          .foregroundColor(.secondary)

        // 目录授权书签
        HStack {
          Text(l10n: "bookmarks_count_label")
            .frame(width: 120, alignment: .leading)

          Text("\(bookmarkCount) \(L10n.string("bookmarks_items_unit")) (\(FormatUtils.fileSizeString(bookmarkSize)))")
            .font(.system(.body, design: .monospaced))
            .frame(height: 20, alignment: .leading)
        }

        Text(l10n: "bookmarks_description")
          .font(.caption)
          .foregroundColor(.secondary)
      }

      Divider()

      // 缓存操作
      VStack(alignment: .leading, spacing: 16) {
        Text(l10n: "cache_actions_group")
          .fontWeight(.medium)

        HStack(spacing: 12) {
          Button(action: { showingClearConfirmation = true }) {
            HStack(spacing: 6) {
              Image(systemName: "trash")
              Text(l10n: "clear_cache_button")
            }
          }
          .buttonStyle(.borderedProminent)
          .tint(.red)
          .disabled(cacheSize == 0)

          Button(action: openCacheDirectory) {
            HStack(spacing: 6) {
              Image(systemName: "folder")
              Text(l10n: "open_cache_directory")
            }
          }
          .buttonStyle(.bordered)

          Button(action: { showingClearBookmarksConfirmation = true }) {
            HStack(spacing: 6) {
              Image(systemName: "bookmark.slash")
              Text(l10n: "clear_bookmarks_button")
            }
          }
          .buttonStyle(.bordered)
          .disabled(bookmarkCount == 0)
        }

        Text(l10n: "cache_actions_description")
          .font(.caption)
          .foregroundColor(.secondary)
      }

      Spacer().frame(height: 20)
    }
    .frame(maxWidth: .infinity, alignment: .topLeading)
  }

  private func refreshCacheSize() {
    refreshGeneration &+= 1
    let currentGeneration = refreshGeneration

    refreshTask?.cancel()
    isLoading = true

    let task = Task {
      let size = await DiskCache.shared.getCacheSize()
      if Task.isCancelled { return }
      await MainActor.run {
        guard refreshGeneration == currentGeneration else { return }
        cacheSize = size

        // 同时更新书签统计
        let manager = DirectoryBookmarkManager.shared
        bookmarkCount = manager.getBookmarkCount()
        bookmarkSize = manager.getBookmarkSize()

        isLoading = false
        refreshTask = nil
      }
    }

    refreshTask = task
  }

  private func clearCache() async {
    refreshTask?.cancel()
    isLoading = true
    do {
      try await DiskCache.shared.clearCache()
      await MainActor.run {
        cacheSize = 0
        isLoading = false
      }
      refreshCacheSize()
    } catch {
      await MainActor.run {
        isLoading = false
        // 可以在这里添加错误提示
      }
    }
  }

  private func openCacheDirectory() {
    Task {
      let cacheURL = await DiskCache.shared.cacheDirectoryURL()
      _ = await MainActor.run {
        NSWorkspace.shared.open(cacheURL)
      }
    }
  }

  private func clearBookmarks() {
    DirectoryBookmarkManager.shared.clearAllBookmarks()
    bookmarkCount = 0
    bookmarkSize = 0
  }

}

// 预览
#Preview {
  CacheSettingsView()
}
