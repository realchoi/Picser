//
//  ContentView.swift
//  PicTube
//
//  Created by Eric Cai on 2025/8/18.
//

import Foundation
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

/// EXIF 信息提取错误类型
enum ExifExtractionError: Error {
  case failedToCreateImageSource
  case failedToExtractProperties
}

struct ContentView: View {
  // 使用 @State 属性包装器来声明一个状态变量
  // 当这个变量改变时，SwiftUI 会自动刷新相关的视图
  @State private var imageURLs: [URL] = []  // 文件夹中所有图片的 URL 列表
  @State private var selectedImageURL: URL?  // 当前选中的图片 URL
  @FocusState private var isFocused: Bool  // 焦点状态管理
  @State private var sidebarVisibility: NavigationSplitViewVisibility = .detailOnly  // 侧边栏可见性控制

  // EXIF 信息相关状态
  @State private var showingExifInfo = false  // 是否显示 EXIF 信息弹窗
  @State private var currentExifInfo: ExifInfo?  // 当前图片的 EXIF 信息
  @State private var isLoadingExif = false  // 是否正在加载 EXIF 信息
  @State private var exifErrorMessage: String?  // EXIF 错误消息
  @State private var showingExifError = false  // 是否显示 EXIF 错误弹窗

  // 接收设置对象
  @EnvironmentObject var appSettings: AppSettings

  var body: some View {
    NavigationSplitView(columnVisibility: $sidebarVisibility) {
      SidebarView(imageURLs: imageURLs, selectedImageURL: selectedImageURL) { url in
        selectedImageURL = url
      }
      .frame(minWidth: 150)
    } detail: {
      DetailView(imageURLs: imageURLs, selectedImageURL: selectedImageURL, onOpen: openFileOrFolder)
        .environmentObject(appSettings)
    }
    .onChange(of: imageURLs) { _, newURLs in
      // 当图片列表变化时，更新侧边栏可见性
      if newURLs.isEmpty {
        sidebarVisibility = .detailOnly
      } else {
        sidebarVisibility = .all
      }
    }
    .onChange(of: selectedImageURL) { _, newURL in
      guard let newURL else { return }
      prefetchNeighbors(around: newURL)
    }
    .onKeyPress { press in
      handleKeyPress(press)
      return .handled
    }
    .focusable()  // 确保视图可以获得焦点
    .focused($isFocused)  // 绑定焦点状态
    .onAppear {
      // 确保视图在出现时获得焦点
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
        isFocused = true
      }
    }
    .onTapGesture {
      // 点击时重新获得焦点
      isFocused = true
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
        // 给 toolbar 的打开文件夹按钮添加一个鼠标悬停的提示文本，且弹窗提示的速度尽量快
        .help(NSLocalizedString("open_file_or_folder_button", comment: "Open Image/Folder"))
      }
      // 再添加一个工具栏按钮，用来查看图片的 exif 信息
      if selectedImageURL != nil {
        ToolbarItem {
          Button {
            showExifInfo()
          } label: {
            HStack(spacing: 4) {
              if isLoadingExif {
                ProgressView()
                  .scaleEffect(0.8)
                  .frame(width: 16, height: 16)
              } else {
                Image(systemName: "info.circle")
              }

              if isLoadingExif {
                Text(NSLocalizedString("loading_text", comment: "Loading..."))
                  .font(.caption)
              }
            }
          }
          .disabled(isLoadingExif)
          .help(
            isLoadingExif
              ? NSLocalizedString("exif_loading_hint", comment: "Loading EXIF information...")
              : NSLocalizedString("exif_info_button", comment: "Show Exif Info"))
        }
      }
    }
    // 当窗口大小变化时，你可能希望重置缩放和偏移
    // .onChange(of: geometry.size) { ... } (需要 GeometryReader)
    .sheet(isPresented: $showingExifInfo) {
      if let exifInfo = currentExifInfo {
        ExifInfoView(exifInfo: exifInfo)
      }
    }
    .alert(
      NSLocalizedString("exif_loading_error_title", comment: "EXIF Loading Error"),
      isPresented: $showingExifError
    ) {
      Button(NSLocalizedString("ok_button", comment: "OK"), role: .cancel) {}
    } message: {
      if let errorMessage = exifErrorMessage {
        Text(errorMessage)
      }
    }
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

  /// 显示图片的 exif 信息
  private func showExifInfo() {
    guard let currentURL = selectedImageURL else {
      exifErrorMessage = NSLocalizedString("exif_no_image_selected", comment: "No image selected")
      showingExifError = true
      return
    }

    // 防止重复点击
    guard !isLoadingExif else { return }

    isLoadingExif = true

    Task {
      do {
        let exifInfo = try await loadExifInfo(for: currentURL)
        await MainActor.run {
          self.isLoadingExif = false
          self.currentExifInfo = exifInfo
          self.showingExifInfo = true
        }
      } catch ExifExtractionError.failedToCreateImageSource {
        await MainActor.run {
          self.isLoadingExif = false
          self.exifErrorMessage = NSLocalizedString(
            "exif_file_read_error", comment: "File read error")
          self.showingExifError = true
        }
      } catch ExifExtractionError.failedToExtractProperties {
        await MainActor.run {
          self.isLoadingExif = false
          self.exifErrorMessage = NSLocalizedString(
            "exif_metadata_extract_error", comment: "Metadata extract error")
          self.showingExifError = true
        }
      } catch {
        await MainActor.run {
          self.isLoadingExif = false
          self.exifErrorMessage = "获取 EXIF 信息时发生错误：\(error.localizedDescription)"
          self.showingExifError = true
        }
      }
    }
  }

  /// 加载图片的 EXIF 信息
  private func loadExifInfo(for url: URL) async throws -> ExifInfo {
    // 首先尝试从缓存获取 EXIF 数据
    if let metadata = await DiskCache.shared.retrieve(forKey: url.path) {
      let exifDict = metadata.getExifDictionary()
      if !exifDict.isEmpty {
        return ExifInfo.from(exifDictionary: exifDict, fileName: url.lastPathComponent)
      }
    }

    // 如果缓存中没有，直接从文件提取 EXIF 数据
    return try await extractExifInfoFromFile(url: url)
  }

  /// 直接从文件提取 EXIF 信息
  private func extractExifInfoFromFile(url: URL) async throws -> ExifInfo {
    return try await Task.detached(priority: .userInitiated) {
      guard let imageSource = CGImageSourceCreateWithURL(url as CFURL, nil) else {
        throw ExifExtractionError.failedToCreateImageSource
      }

      guard
        let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [CFString: Any]
      else {
        throw ExifExtractionError.failedToExtractProperties
      }

      // 获取文件属性
      let attributes = try FileManager.default.attributesOfItem(atPath: url.path)

      // 构建 EXIF 数据字典
      var exifDict: [String: Any] = [:]

      // 添加基础属性
      if let width = properties[kCGImagePropertyPixelWidth] as? Int {
        exifDict["ImageWidth"] = width
      }
      if let height = properties[kCGImagePropertyPixelHeight] as? Int {
        exifDict["ImageHeight"] = height
      }

      exifDict["FileSize"] = attributes[.size] as? Int64 ?? 0

      if let modificationDate = attributes[.modificationDate] as? Date {
        exifDict["FileModificationDate"] = modificationDate.timeIntervalSince1970
      }

      // 提取各种 EXIF 数据
      if let exifProperties = properties[kCGImagePropertyExifDictionary] as? [CFString: Any] {
        for (key, value) in exifProperties {
          exifDict["Exif_\(key)"] = value
        }
      }

      if let tiffProperties = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any] {
        for (key, value) in tiffProperties {
          exifDict["TIFF_\(key)"] = value
        }
      }

      if let gpsProperties = properties[kCGImagePropertyGPSDictionary] as? [CFString: Any] {
        for (key, value) in gpsProperties {
          exifDict["GPS_\(key)"] = value
        }
      }

      return ExifInfo.from(exifDictionary: exifDict, fileName: url.lastPathComponent)
    }.value
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

  /// 处理键盘按键事件，实现图片切换功能
  private func handleKeyPress(_ press: KeyPress) {
    guard !imageURLs.isEmpty, let currentURL = selectedImageURL else {
      // print("handleKeyPress: 图片列表为空或没有选中的图片")
      return
    }

    let currentIndex = imageURLs.firstIndex(of: currentURL) ?? 0
    let totalCount = imageURLs.count

    // print("handleKeyPress: 按键 \(press.key), 当前索引: \(currentIndex), 总数: \(totalCount)")

    switch appSettings.imageNavigationKey {
    case .leftRight:
      // 左右方向键：左键上一张，右键下一张
      if press.key == .leftArrow {
        let newIndex = (currentIndex - 1 + totalCount) % totalCount
        // print("左箭头: 从 \(currentIndex) 切换到 \(newIndex)")
        navigateToImage(at: newIndex)
      } else if press.key == .rightArrow {
        let newIndex = (currentIndex + 1) % totalCount
        // print("右箭头: 从 \(currentIndex) 切换到 \(newIndex)")
        navigateToImage(at: newIndex)
      }

    case .upDown:
      // 上下方向键：上键上一张，下键下一张
      if press.key == .upArrow {
        let newIndex = (currentIndex - 1 + totalCount) % totalCount
        // print("上箭头: 从 \(currentIndex) 切换到 \(newIndex)")
        navigateToImage(at: newIndex)
      } else if press.key == .downArrow {
        let newIndex = (currentIndex + 1) % totalCount
        // print("下箭头: 从 \(currentIndex) 切换到 \(newIndex)")
        navigateToImage(at: newIndex)
      }

    case .pageUpDown:
      // PageUp/PageDown：PageUp上一张，PageDown下一张
      if press.key == .pageUp {
        let newIndex = (currentIndex - 1 + totalCount) % totalCount
        // print("PageUp: 从 \(currentIndex) 切换到 \(newIndex)")
        navigateToImage(at: newIndex)
      } else if press.key == .pageDown {
        let newIndex = (currentIndex + 1) % totalCount
        // print("PageDown: 从 \(currentIndex) 切换到 \(newIndex)")
        navigateToImage(at: newIndex)
      }
    }

    // 确保按键后焦点保持
    DispatchQueue.main.async {
      isFocused = true
    }
  }

  /// 导航到指定索引的图片
  private func navigateToImage(at index: Int) {
    guard index >= 0 && index < imageURLs.count else {
      print("navigateToImage: 无效索引 \(index), 总数: \(imageURLs.count)")
      return
    }
    // print("navigateToImage: 切换到索引 \(index), URL: \(imageURLs[index].lastPathComponent)")
    selectedImageURL = imageURLs[index]
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
        systemImage: "folder"
      )
      .padding(8)  // 添加按钮的内边距
    }
    .buttonStyle(.borderedProminent)
    .controlSize(.extraLarge)
    .font(.title2)
    .labelStyle(.titleAndIcon)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}

#Preview {
  ContentView().environmentObject(AppSettings())
}
