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
  // 拖放高亮
  @State private var isDropTargeted = false

  // 接收设置对象
  @EnvironmentObject var appSettings: AppSettings

  var body: some View {
    ZStack {
      NavigationSplitView(columnVisibility: $sidebarVisibility) {
        SidebarView(imageURLs: imageURLs, selectedImageURL: selectedImageURL) { url in
          selectedImageURL = url
        }
        .frame(minWidth: 150)
      } detail: {
        DetailView(
          imageURLs: imageURLs,
          selectedImageURL: selectedImageURL,
          onOpen: openFileOrFolder,
          showingExifInfo: $showingExifInfo,
          exifInfo: currentExifInfo
        )
        .environmentObject(appSettings)
      }
      // 拖放高亮层
      if isDropTargeted {
        DropOverlay()
          .transition(.opacity.animation(.easeInOut(duration: 0.12)))
          .allowsHitTesting(false)
      }
    }
    // 支持将文件/文件夹拖放到窗口打开
    .onDrop(of: [UTType.fileURL], isTargeted: $isDropTargeted) { providers in
      handleDropProviders(providers)
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
    // 菜单命令触发：打开文件/文件夹（⌘O）
    .onReceive(NotificationCenter.default.publisher(for: .openFileOrFolderRequested)) { _ in
      openFileOrFolder()
    }
    // 处理从“最近打开”菜单发来的打开指定文件夹请求
    .onReceive(NotificationCenter.default.publisher(for: .openFolderURLRequested)) { notif in
      guard let url = notif.object as? URL else { return }
      Task {
        let uniqueSorted = await computeImageURLs(from: [url])
        if uniqueSorted.isEmpty { return }
        await MainActor.run {
          self.imageURLs = uniqueSorted
          self.selectedImageURL = uniqueSorted.first
        }
      }
    }
    .toolbar {
      ToolbarItem {
        Button {
          openFileOrFolder()
        } label: {
          Label(
            "open_file_or_folder_button".localized,
            systemImage: "folder")
        }
        // 给 toolbar 的打开文件夹按钮添加一个鼠标悬停的提示文本，且弹窗提示的速度尽量快
        .help("open_file_or_folder_button".localized)
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
                Text("loading_text".localized)
                  .font(.caption)
              }
            }
          }
          .disabled(isLoadingExif)
          .help(
            isLoadingExif
              ? "exif_loading_hint".localized
              : "exif_info_button".localized)
        }
      }
    }
    // 当窗口大小变化时，你可能希望重置缩放和偏移
    // .onChange(of: geometry.size) { ... } (需要 GeometryReader)
    // 改为在 DetailView 中以可拖拽 overlay 展示 EXIF，取消 sheet
    .alert(
      "exif_loading_error_title".localized,
      isPresented: $showingExifError
    ) {
      Button("ok_button".localized, role: .cancel) {}
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

      // 记录最近打开（按图开图：文件归属其父目录）
      RecentOpensManager.shared.add(urls: urls)

      // 后台线程枚举与排序，主线程仅更新状态
      Task {
        let uniqueSorted = await computeImageURLs(from: urls)
        if uniqueSorted.isEmpty { return }
        await MainActor.run {
          self.imageURLs = uniqueSorted
          self.selectedImageURL = uniqueSorted.first
        }
      }
    }
  }

  /// 处理拖放进窗口的文件/文件夹 URL 提供者
  private func handleDropProviders(_ providers: [NSItemProvider]) -> Bool {
    guard !providers.isEmpty else { return false }

    let group = DispatchGroup()
    var droppedURLs: [URL] = []

    for provider in providers {
      if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
        group.enter()
        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
          defer { group.leave() }
          if let url = item as? URL {
            droppedURLs.append(url)
          } else if let data = item as? Data,
                    let str = String(data: data, encoding: .utf8),
                    let url = URL(string: str) {
            droppedURLs.append(url)
          }
        }
      }
    }

    group.notify(queue: .main) {
      guard !droppedURLs.isEmpty else { return }
      // 记录最近打开
      RecentOpensManager.shared.add(urls: droppedURLs)
      Task {
        let uniqueSorted = await computeImageURLs(from: droppedURLs)
        if uniqueSorted.isEmpty { return }
        await MainActor.run {
          self.imageURLs = uniqueSorted
          self.selectedImageURL = uniqueSorted.first
        }
      }
    }
    return true
  }

  /// 显示图片的 exif 信息
  private func showExifInfo() {
    guard let currentURL = selectedImageURL else {
      exifErrorMessage = "exif_no_image_selected".localized
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
          self.exifErrorMessage = "exif_file_read_error".localized
          self.showingExifError = true
        }
      } catch ExifExtractionError.failedToExtractProperties {
        await MainActor.run {
          self.isLoadingExif = false
          self.exifErrorMessage = "exif_metadata_extract_error".localized
          self.showingExifError = true
        }
      } catch {
        await MainActor.run {
          self.isLoadingExif = false
          // 使用本地化的通用错误提示
          self.exifErrorMessage = "exif_unexpected_error".localized
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
    // 允许的图片扩展名（小写）
    let imageExtensions = ["jpg", "jpeg", "png", "gif", "heic", "tiff", "webp"]

    return await withCheckedContinuation { continuation in
      DispatchQueue.global(qos: .userInitiated).async {
        var collected: [URL] = []
        let fm = FileManager.default

        // 1) 枚举输入源（文件/目录），收集图片 URL
        for url in inputs {
          if url.hasDirectoryPath {
            if let files = try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: nil) {
              collected.append(contentsOf: files.filter { imageExtensions.contains($0.pathExtension.lowercased()) })
            }
          } else if imageExtensions.contains(url.pathExtension.lowercased()) {
            collected.append(url)
          }
        }

        // 2) 使用字典进行去重，保持首次出现顺序（避免 Set 破坏顺序）
        var seen: [String: Bool] = [:]  // key: standardized path
        var unique: [URL] = []
        unique.reserveCapacity(collected.count)
        for url in collected {
          let key = url.standardizedFileURL.path
          if seen[key] == nil {
            seen[key] = true
            unique.append(url)
          }
        }

        // 3) 稳定排序：优先目录路径，其次文件名的自然数值排序
        // 使用 localizedStandardCompare 提供 Finder 风格的“自然排序”
        let enumerated = unique.enumerated().map { ($0.offset, $0.element) }
        let sortedStable = enumerated.sorted { lhs, rhs in
          let (li, l) = lhs
          let (ri, r) = rhs
          let lDir = l.deletingLastPathComponent().path
          let rDir = r.deletingLastPathComponent().path

          if lDir != rDir {
            return lDir.localizedStandardCompare(rDir) == .orderedAscending
          }

          let lName = l.lastPathComponent
          let rName = r.lastPathComponent
          let nameOrder = lName.localizedStandardCompare(rName)
          if nameOrder != .orderedSame {
            return nameOrder == .orderedAscending
          }

          // 兜底：在完全相同的比较键时，按原始索引（稳定）
          return li < ri
        }.map { $0.1 }

        continuation.resume(returning: sortedStable)
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

    // ESC 关闭 EXIF 浮动面板
    if press.key == .escape {
      if showingExifInfo { showingExifInfo = false }
      // 保持焦点
      DispatchQueue.main.async { isFocused = true }
      return
    }

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
  @Binding var showingExifInfo: Bool
  let exifInfo: ExifInfo?
  @EnvironmentObject var appSettings: AppSettings

  // EXIF 浮动面板拖拽状态
  @State private var exifOffset: CGSize = .zero
  @GestureState private var exifDrag: CGSize = .zero

  // 记住上次位置（跨会话）
  @AppStorage("exifPanelOffsetX") private var savedExifOffsetX: Double = .nan
  @AppStorage("exifPanelOffsetY") private var savedExifOffsetY: Double = .nan

  // 面板尺寸与边距
  private let panelSize = CGSize(width: 600, height: 500)
  private let panelPadding: CGFloat = 12
  private let snapThreshold: CGFloat = 100

  var body: some View {
    GeometryReader { geo in
      Group {
        if imageURLs.isEmpty {
          EmptyHint(onOpen: onOpen)
        } else if let url = selectedImageURL {
          ZStack(alignment: .topLeading) {
            AsyncZoomableImageContainer(url: url)
              .frame(maxWidth: .infinity, maxHeight: .infinity)

            if showingExifInfo, let info = exifInfo {
              ExifInfoView(exifInfo: info, onClose: { showingExifInfo = false })
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .shadow(color: .black.opacity(0.25), radius: 12, x: 0, y: 6)
                .padding(panelPadding)
                .offset(
                  x: exifOffset.width + exifDrag.width,
                  y: exifOffset.height + exifDrag.height
                )
                .gesture(
                  DragGesture()
                    .updating($exifDrag) { value, state, _ in
                      state = value.translation
                    }
                    .onEnded { value in
                      // 计算拖拽后的新位置（基于左上角）
                      var newX = exifOffset.width + value.translation.width
                      var newY = exifOffset.height + value.translation.height

                      // 约束到可视区域内
                      let minX = panelPadding
                      let minY = panelPadding
                      let maxX = max(minX, geo.size.width - panelSize.width - panelPadding)
                      let maxY = max(minY, geo.size.height - panelSize.height - panelPadding)
                      newX = min(max(newX, minX), maxX)
                      newY = min(max(newY, minY), maxY)

                      // 计算吸附到四角（在阈值内时吸附）
                      let topLeft = CGPoint(x: minX, y: minY)
                      let topRight = CGPoint(x: maxX, y: minY)
                      let bottomLeft = CGPoint(x: minX, y: maxY)
                      let bottomRight = CGPoint(x: maxX, y: maxY)

                      let current = CGPoint(x: newX, y: newY)
                      let distances: [(CGPoint, CGFloat)] = [topLeft, topRight, bottomLeft, bottomRight]
                        .map { corner in
                          let dx = current.x - corner.x
                          let dy = current.y - corner.y
                          return (corner, sqrt(dx*dx + dy*dy))
                        }
                      if let nearest = distances.min(by: { $0.1 < $1.1 }), nearest.1 <= snapThreshold {
                        newX = nearest.0.x
                        newY = nearest.0.y
                      }

                      exifOffset = CGSize(width: newX, height: newY)
                      savedExifOffsetX = newX.isFinite ? Double(newX) : .nan
                      savedExifOffsetY = newY.isFinite ? Double(newY) : .nan
                    }
                )
                .onAppear {
                  // 首次出现：若有保存位置则使用；否则默认右上角
                  if savedExifOffsetX.isNaN || savedExifOffsetY.isNaN {
                    let minX = panelPadding
                    let minY = panelPadding
                    let maxX = max(minX, geo.size.width - panelSize.width - panelPadding)
                    let y = minY
                    exifOffset = CGSize(width: maxX, height: y)
                  } else {
                    let minX = panelPadding
                    let minY = panelPadding
                    let maxX = max(minX, geo.size.width - panelSize.width - panelPadding)
                    let maxY = max(minY, geo.size.height - panelSize.height - panelPadding)
                    let x = min(max(CGFloat(savedExifOffsetX), minX), maxX)
                    let y = min(max(CGFloat(savedExifOffsetY), minY), maxY)
                    exifOffset = CGSize(width: x, height: y)
                  }
                }
            }
          }
          // 当窗口尺寸变化时，确保面板仍在可视范围内
          .onChange(of: geo.size) { _, newSize in
            let minX = panelPadding
            let minY = panelPadding
            let maxX = max(minX, newSize.width - panelSize.width - panelPadding)
            let maxY = max(minY, newSize.height - panelSize.height - panelPadding)
            let x = min(max(exifOffset.width, minX), maxX)
            let y = min(max(exifOffset.height, minY), maxY)
            if x != exifOffset.width || y != exifOffset.height {
              exifOffset = CGSize(width: x, height: y)
              savedExifOffsetX = Double(x)
              savedExifOffsetY = Double(y)
            }
          }
        } else {
          Text("select_image_hint".localized)
            .font(.title)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
      }
    }
  }
}

private struct EmptyHint: View {
  let onOpen: () -> Void

  var body: some View {
    VStack(spacing: 16) {
      Button {
        onOpen()
      } label: {
        Label(
          "open_file_or_folder_button".localized,
          systemImage: "folder"
        )
        .padding(8)
      }
      .buttonStyle(.borderedProminent)
      .controlSize(.extraLarge)
      .font(.title2)
      .labelStyle(.titleAndIcon)

      // 额外提示：支持拖拽文件/文件夹打开
      HStack(spacing: 8) {
        Image(systemName: "tray.and.arrow.down")
          .foregroundStyle(.secondary)
        Text("empty_drag_hint".localized)
          .foregroundStyle(.secondary)
      }
      .font(.body)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}

// 拖放高亮层
private struct DropOverlay: View {
  var body: some View {
    ZStack {
      // 半透明蒙层
      Color.black.opacity(0.12)
        .ignoresSafeArea()

      // 中心提示卡片
      VStack(spacing: 8) {
        Image(systemName: "square.and.arrow.down.on.square")
          .font(.system(size: 36, weight: .medium))
          .foregroundStyle(Color.accentColor)
        Text("drop_overlay_title".localized)
          .font(.title3)
          .bold()
        Text("drop_overlay_subtitle".localized)
          .font(.callout)
          .foregroundStyle(.secondary)
      }
      .padding(20)
      .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
      .overlay(
        RoundedRectangle(cornerRadius: 16, style: .continuous)
          .stroke(Color.accentColor.opacity(0.8), style: StrokeStyle(lineWidth: 2, dash: [8, 6]))
      )
      .shadow(radius: 12)
    }
  }
}

#Preview {
  ContentView().environmentObject(AppSettings())
}
