//
//  CacheSettingsView.swift
//  PicTube
//
//  Created by Eric Cai on 2025/8/22.
//

import AppKit
import SwiftUI

struct CacheSettingsView: View {
  @State private var cacheSize: Int64 = 0
  @State private var isLoading = false
  @State private var showingClearConfirmation = false

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 20) {
        Text(NSLocalizedString("cache_settings_title", comment: "Cache settings title"))
          .font(.title2)
          .fontWeight(.semibold)

        Divider()

        // 缓存信息显示
        VStack(alignment: .leading, spacing: 16) {
          Text(NSLocalizedString("cache_info_group", comment: "Cache info group"))
            .fontWeight(.medium)

          HStack {
            Text(NSLocalizedString("cache_size_label", comment: "Cache size label"))
              .frame(width: 120, alignment: .leading)

            // 使用固定尺寸的容器来避免布局跳变
            ZStack {
              if isLoading {
                ProgressView()
                  .scaleEffect(0.8)
              } else {
                Text(formatFileSize(cacheSize))
                  .font(.system(.body, design: .monospaced))
              }
            }
            .frame(width: 80, height: 20, alignment: .leading)

            Button(action: refreshCacheSize) {
              Image(systemName: "arrow.clockwise")
                .font(.caption)
            }
            .buttonStyle(.borderless)
            .help(NSLocalizedString("refresh_cache_size", comment: "Refresh cache size"))
          }

          Text(NSLocalizedString("cache_size_description", comment: "Cache size description"))
            .font(.caption)
            .foregroundColor(.secondary)
        }

        Divider()

        // 缓存操作
        VStack(alignment: .leading, spacing: 16) {
          Text(NSLocalizedString("cache_actions_group", comment: "Cache actions group"))
            .fontWeight(.medium)

          HStack(spacing: 12) {
            Button(action: { showingClearConfirmation = true }) {
              HStack(spacing: 6) {
                Image(systemName: "trash")
                Text(NSLocalizedString("clear_cache_button", comment: "Clear cache button"))
              }
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .disabled(cacheSize == 0)

            Button(action: openCacheDirectory) {
              HStack(spacing: 6) {
                Image(systemName: "folder")
                Text(NSLocalizedString("open_cache_directory", comment: "Open cache directory"))
              }
            }
            .buttonStyle(.bordered)
          }

          Text(NSLocalizedString("cache_actions_description", comment: "Cache actions description"))
            .font(.caption)
            .foregroundColor(.secondary)
        }

        Spacer(minLength: 20)
      }
      .padding()
      .frame(maxWidth: .infinity, minHeight: 350, alignment: .topLeading)
    }
    .scrollIndicators(.visible)
    .onAppear {
      refreshCacheSize()
    }
    .alert(
      NSLocalizedString("clear_cache_alert_title", comment: "Clear cache alert title"),
      isPresented: $showingClearConfirmation
    ) {
      Button(NSLocalizedString("cancel_button", comment: "Cancel button"), role: .cancel) {}
      Button(NSLocalizedString("clear_button", comment: "Clear button"), role: .destructive) {
        Task {
          await clearCache()
        }
      }
    } message: {
      Text(NSLocalizedString("clear_cache_alert_message", comment: "Clear cache alert message"))
    }
  }

  // MARK: - Private Methods

  private func refreshCacheSize() {
    isLoading = true
    Task {
      let size = await DiskCache.shared.getCacheSize()
      await MainActor.run {
        cacheSize = size
        isLoading = false
      }
    }
  }

  private func clearCache() async {
    isLoading = true
    do {
      try await DiskCache.shared.clearCache()
      await MainActor.run {
        cacheSize = 0
        isLoading = false
      }
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

  private func formatFileSize(_ bytes: Int64) -> String {
    let formatter = ByteCountFormatter()
    formatter.allowedUnits = [.useKB, .useMB, .useGB]
    formatter.countStyle = .file
    return formatter.string(fromByteCount: bytes)
  }
}

// 预览
#Preview {
  CacheSettingsView()
}
