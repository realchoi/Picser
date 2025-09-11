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
          // 选中缩略图后，主动把键盘焦点交还给主视图，确保可用按键切换
          DispatchQueue.main.async { isFocused = true }
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
      // 保持主视图焦点，避免 List 抢占导致按键无效
      isFocused = true
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
    // 处理从“最近打开”菜单发来的打开指定文件夹请求（统一走 FileOpenService）
    .onReceive(NotificationCenter.default.publisher(for: .openFolderURLRequested)) { notif in
      guard let url = notif.object as? URL else { return }
      Task {
        let uniqueSorted = await FileOpenService.discover(from: [url], recordRecents: false)
        await MainActor.run { applyImages(uniqueSorted) }
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
    Task {
      let uniqueSorted = await FileOpenService.openFileOrFolder()
      await MainActor.run { applyImages(uniqueSorted) }
    }
  }

  /// 处理拖放进窗口的文件/文件夹 URL 提供者
  private func handleDropProviders(_ providers: [NSItemProvider]) -> Bool {
    guard !providers.isEmpty else { return false }
    Task {
      let uniqueSorted = await FileOpenService.processDropProviders(providers)
      await MainActor.run { applyImages(uniqueSorted) }
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
        let exifInfo = try await ExifExtractor.loadExifInfo(for: currentURL)
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
  // computeImageURLs moved to ImageDiscovery
}

// MARK: - Helpers
extension ContentView {
  private func applyImages(_ urls: [URL]) {
    guard !urls.isEmpty else { return }
    self.imageURLs = urls
    self.selectedImageURL = urls.first
  }

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

    if let newIndex = ImageNavigation.nextIndex(
      for: press.key,
      mode: appSettings.imageNavigationKey,
      currentIndex: currentIndex,
      totalCount: totalCount
    ) {
      navigateToImage(at: newIndex)
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

// SidebarView extracted to PicTube/Views/SidebarView.swift

// DetailView extracted to PicTube/Views/DetailView.swift

// EmptyHint extracted to PicTube/Views/EmptyHint.swift

// DropOverlay extracted to PicTube/Views/DropOverlay.swift

#Preview {
  ContentView().environmentObject(AppSettings())
}
