//
//  ContentView.swift
//  PicTube
//
//  Created by Eric Cai on 2025/8/18.
//

import Foundation
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
  // 使用 @State 属性包装器来声明一个状态变量
  // 当这个变量改变时，SwiftUI 会自动刷新相关的视图
  @State private var imageURLs: [URL] = []  // 文件夹中所有图片的 URL 列表
  @State private var selectedImageURL: URL?  // 当前选中的图片 URL

  // 接收设置对象
  @EnvironmentObject var appSettings: AppSettings

  var body: some View {
    NavigationSplitView {
      SidebarView(imageURLs: imageURLs, selectedImageURL: selectedImageURL) { url in
        selectedImageURL = url
      }
      .frame(minWidth: 150)
    } detail: {
      DetailView(imageURLs: imageURLs, selectedImageURL: selectedImageURL, onOpen: openFileOrFolder)
        .environmentObject(appSettings)
    }
    .onChange(of: selectedImageURL) { _, newURL in
      guard let newURL else { return }
      prefetchNeighbors(around: newURL)
    }
    .toolbar {
      ToolbarItem {
        Button {
          openFileOrFolder()
        } label: {
          Label(
            NSLocalizedString("open_file_or_folder_button", comment: "Open Image/Folder"),
            systemImage: "folder")
        }
      }
    }
    // 当窗口大小变化时，你可能希望重置缩放和偏移
    // .onChange(of: geometry.size) { ... } (需要 GeometryReader)
  }

  private func openFileOrFolder() {
    let openPanel = NSOpenPanel()
    openPanel.canChooseFiles = true
    openPanel.canChooseDirectories = true
    openPanel.allowsMultipleSelection = true
    openPanel.allowedContentTypes = [UTType.image]

    if openPanel.runModal() == .OK {
      let urls = openPanel.urls
      if urls.isEmpty { return }

      // 后台线程枚举与排序，主线程仅更新状态
      Task {
        let uniqueSorted = await computeImageURLs(from: urls)
        if uniqueSorted.isEmpty { return }
        self.imageURLs = uniqueSorted
        self.selectedImageURL = uniqueSorted.first
      }
    }
  }

  // 在后台线程枚举与筛选图片，避免阻塞主线程
  private func computeImageURLs(from inputs: [URL]) async -> [URL] {
    let imageExtensions = ["jpg", "jpeg", "png", "gif", "heic", "tiff", "webp"]
    return await withCheckedContinuation { continuation in
      DispatchQueue.global(qos: .userInitiated).async {
        var collected: [URL] = []
        let fm = FileManager.default
        for url in inputs {
          if url.hasDirectoryPath {
            if let files = try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: nil) {
              collected.append(
                contentsOf: files.filter { imageExtensions.contains($0.pathExtension.lowercased()) }
              )
            }
          } else if imageExtensions.contains(url.pathExtension.lowercased()) {
            collected.append(url)
          }
        }
        let result = Array(Set(collected)).sorted { $0.lastPathComponent < $1.lastPathComponent }
        continuation.resume(returning: result)
      }
    }
  }
}

// MARK: - Helpers
extension ContentView {
  private func prefetchNeighbors(around url: URL) {
    guard let idx = imageURLs.firstIndex(of: url) else { return }
    var neighbors: [URL] = []
    if idx > 0 { neighbors.append(imageURLs[idx - 1]) }
    if idx + 1 < imageURLs.count { neighbors.append(imageURLs[idx + 1]) }
    // 仅预热缩略图，降低内存与 IO
    let scale = NSScreen.main?.backingScaleFactor ?? 2.0
    ThumbnailService.prefetch(urls: neighbors, size: CGSize(width: 120, height: 120), scale: scale)
    // 额外：预解码较低像素的下采样图，优先速度（约 2048px）
    ImageLoader.shared.prefetch(urls: neighbors)
  }
}

// MARK: - Subviews

private struct SidebarView: View {
  let imageURLs: [URL]
  let selectedImageURL: URL?
  let onSelect: (URL) -> Void

  var body: some View {
    List {
      ForEach(imageURLs, id: \.self) { url in
        ZStack(alignment: .bottomLeading) {
          ThumbnailImageView(url: url, height: 80)
            .cornerRadius(8)

          Text(url.lastPathComponent)
            .font(.caption)
            .lineLimit(1)
            .foregroundColor(.white)
            .padding(4)
            .background(Color.black.opacity(0.6))
            .cornerRadius(4)
            .padding(4)
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .onTapGesture { onSelect(url) }
        .overlay(
          RoundedRectangle(cornerRadius: 8)
            .stroke((selectedImageURL == url) ? Color.accentColor : Color.clear, lineWidth: 2)
        )
      }
    }
  }
}

private struct DetailView: View {
  let imageURLs: [URL]
  let selectedImageURL: URL?
  let onOpen: () -> Void
  @EnvironmentObject var appSettings: AppSettings

  var body: some View {
    Group {
      if imageURLs.isEmpty {
        EmptyHint(onOpen: onOpen)
      } else if let url = selectedImageURL {
        AsyncZoomableImageContainer(url: url)
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else {
        Text("请在左侧选择一张图片")
          .font(.title)
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      }
    }
  }
}

private struct EmptyHint: View {
  let onOpen: () -> Void

  var body: some View {
    Button {
      onOpen()
    } label: {
      Label(
        NSLocalizedString("open_file_or_folder_button", comment: "Open Image/Folder"),
        systemImage: "folder")
    }
    .buttonStyle(.borderedProminent)
    .controlSize(.large)
    .font(.title2)
    .labelStyle(.titleAndIcon)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}

#Preview {
  ContentView()
}
