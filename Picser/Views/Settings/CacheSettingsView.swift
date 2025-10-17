//
//  CacheSettingsView.swift
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
        Text(l10n: "cache_settings_title")
          .font(.title2)
          .fontWeight(.semibold)

        Divider()

        // 缓存信息显示
        VStack(alignment: .leading, spacing: 16) {
          Text(l10n: "cache_info_group")
            .fontWeight(.medium)

          HStack {
            Text(l10n: "cache_size_label")
              .frame(width: 120, alignment: .leading)

            // 使用固定尺寸的容器来避免布局跳变
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
          }

          Text(l10n: "cache_actions_description")
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

}

// 预览
#Preview {
  CacheSettingsView()
}
