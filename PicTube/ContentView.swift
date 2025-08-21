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

  // 简化的图片选择绑定，原生 NSScrollView 会自动处理缩放重置
  private var imageSelection: Binding<URL?> {
    Binding {
      selectedImageURL
    } set: { newURL in
      selectedImageURL = newURL
    }
  }

  var body: some View {
    NavigationSplitView {
      // 左侧边栏：显示缩略图列表
      // 重点：List 的 'selection' 参数绑定到 imageSelection
      // 这就是实现点击切换的全部魔法。
      // 当用户点击一行时，SwiftUI 会自动将该行的 `url` 赋值给 `imageSelection`。
      List(imageURLs, id: \.self, selection: imageSelection) { url in
        // 使用 ZStack 将图片和文件名叠在一起
        ZStack(alignment: .bottomLeading) {
          // 我们需要异步加载图片或确保图片很小，否则列表会卡顿
          // 但对于这个项目，直接加载是可以的
          if let image = NSImage(contentsOf: url) {
            Image(nsImage: image)
              .resizable()
              .aspectRatio(contentMode: .fill)
              .frame(height: 80)
              .clipped()
              .cornerRadius(8)
          }

          // 文件名蒙层
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
      }
      .frame(minWidth: 150)  // 给侧边栏一个最小宽度
    } detail: {
      // 详情视图：当没有任何图片时，显示一个醒目的“打开图片/文件夹”按钮
      if imageURLs.isEmpty {
        Button {
          openFileOrFolder()
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
      } else if let url = selectedImageURL, let nsImage = NSImage(contentsOf: url) {
        // 使用新的纯SwiftUI实现的ZoomableImageView
        ZoomableImageView(image: nsImage)
          .id(selectedImageURL)  // 关键：强制视图在图片变化时重建
          .frame(maxWidth: CGFloat.infinity, maxHeight: CGFloat.infinity)
      } else {
        Text("请在左侧选择一张图片")
          .font(.title)
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      }
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
    openPanel.allowsMultipleSelection = false
    openPanel.allowedContentTypes = [UTType.image]

    if openPanel.runModal() == .OK {
      guard let url = openPanel.url else { return }
      if url.hasDirectoryPath {
        loadImages(from: url)
      } else {
        let imageExtensions = ["jpg", "jpeg", "png", "gif", "heic", "tiff", "webp"]
        if imageExtensions.contains(url.pathExtension.lowercased()) {
          self.imageURLs = [url]
          self.selectedImageURL = url
        }
      }
    }
  }

  private func openFolder() {
    let openPanel = NSOpenPanel()
    openPanel.canChooseFiles = false
    openPanel.canChooseDirectories = true
    openPanel.allowsMultipleSelection = false

    if openPanel.runModal() == .OK {
      if let folderURL = openPanel.url {
        loadImages(from: folderURL)
      }
    }
  }

  private func loadImages(from folderURL: URL) {
    let fileManager = FileManager.default
    let imageExtensions = ["jpg", "jpeg", "png", "gif", "heic", "tiff", "webp"]

    do {
      let fileURLs = try fileManager.contentsOfDirectory(
        at: folderURL,
        includingPropertiesForKeys: nil
      )
      self.imageURLs = fileURLs.filter { url in
        imageExtensions.contains(url.pathExtension.lowercased())
      }.sorted(by: { $0.lastPathComponent < $1.lastPathComponent })  // 按文件名排序

      // 默认选中第一张图片
      self.selectedImageURL = self.imageURLs.first
      print(
        "加载了 \(self.imageURLs.count) 张图片，默认选中: \(self.imageURLs.first?.lastPathComponent ?? "nil")")
    } catch {
      print(
        "Error while enumerating files \(folderURL.path): \(error.localizedDescription)"
      )
    }
  }
}

#Preview {
  ContentView()
}
