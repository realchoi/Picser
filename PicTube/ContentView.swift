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
  @State private var currentSourceInputs: [URL] = []  // 当前图片列表的来源 URL（文件或文件夹）
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

  // 图像变换（旋转/镜像）状态（按当前选中图片临时生效）
  @State private var imageTransform: ImageTransform = .identity

  // 裁剪状态
  @State private var isCropping: Bool = false
  @State private var cropAspect: CropAspectOption = .freeform
  @State private var showingAddCustomRatio = false
  @State private var customRatioW: String = "1"
  @State private var customRatioH: String = "1"

  // 接收设置对象
  @EnvironmentObject var appSettings: AppSettings

  var body: some View {
    ZStack {
      navigationLayout
      dropHighlightOverlay
    }
    .onDrop(of: [UTType.fileURL], isTargeted: $isDropTargeted) { providers in
      handleDropProviders(providers)
    }
    .onChange(of: imageURLs) { _, newURLs in
      updateSidebarVisibility(for: newURLs)
    }
    .onChange(of: selectedImageURL) { _, newURL in
      handleSelectionChange(newURL)
    }
    .sheet(isPresented: $showingAddCustomRatio) {
      AddCustomRatioSheet { ratio in
        if !isCropping {
          isCropping = true
        }
        cropAspect = .fixed(ratio)
      }
      .environmentObject(appSettings)
    }
    .onKeyPress { press in
      let handled = handleKeyPress(press)
      return handled ? .handled : .ignored
    }
    .focusable()
    .focused($isFocused)
    .onAppear(perform: ensureInitialFocus)
    .onTapGesture { isFocused = true }
    .onReceive(NotificationCenter.default.publisher(for: .openFileOrFolderRequested)) { _ in
      openFileOrFolder()
    }
    .onReceive(NotificationCenter.default.publisher(for: .refreshRequested)) { _ in
      refreshCurrentInputs()
    }
    .onReceive(NotificationCenter.default.publisher(for: .openFolderURLRequested)) { notif in
      guard let url = notif.object as? URL else { return }
      Task {
        let normalized = [url.standardizedFileURL]
        let uniqueSorted = await FileOpenService.discover(from: normalized, recordRecents: false)
        let batch = ImageBatch(inputs: normalized, imageURLs: uniqueSorted)
        await MainActor.run {
          applyImageBatch(batch)
        }
      }
    }
    .onReceive(NotificationCenter.default.publisher(for: .rotateCCWRequested)) { _ in
      imageTransform.rotation = imageTransform.rotation.rotated(by: -90)
    }
    .onReceive(NotificationCenter.default.publisher(for: .rotateCWRequested)) { _ in
      imageTransform.rotation = imageTransform.rotation.rotated(by: 90)
    }
    .onReceive(NotificationCenter.default.publisher(for: .mirrorHRequested)) { _ in
      imageTransform.mirrorH.toggle()
    }
    .onReceive(NotificationCenter.default.publisher(for: .mirrorVRequested)) { _ in
      imageTransform.mirrorV.toggle()
    }
    .onReceive(NotificationCenter.default.publisher(for: .resetTransformRequested)) { _ in
      imageTransform = .identity
    }
    .onReceive(NotificationCenter.default.publisher(for: .cropRectPrepared)) { notif in
      if let rectVal = notif.userInfo?["rect"] as? NSValue {
        handleCropRectPrepared(rectVal.rectValue)
      }
    }
    .toolbar { toolbarContent }
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

  @ViewBuilder
  private var navigationLayout: some View {
    NavigationSplitView(columnVisibility: $sidebarVisibility) {
      sidebarColumn
    } detail: {
      detailColumn
    }
  }

  @ViewBuilder
  private var sidebarColumn: some View {
    SidebarView(imageURLs: imageURLs, selectedImageURL: selectedImageURL) { url in
      selectedImageURL = url
      DispatchQueue.main.async { isFocused = true }
    }
    .frame(minWidth: 150)
  }

  @ViewBuilder
  private var detailColumn: some View {
    DetailView(
      imageURLs: imageURLs,
      selectedImageURL: selectedImageURL,
      onOpen: openFileOrFolder,
      showingExifInfo: $showingExifInfo,
      exifInfo: currentExifInfo,
      transform: imageTransform,
      isCropping: $isCropping,
      cropAspect: $cropAspect,
      showingAddCustomRatio: $showingAddCustomRatio
    )
    .environmentObject(appSettings)
  }

  @ViewBuilder
  private var dropHighlightOverlay: some View {
    if isDropTargeted {
      DropOverlay()
        .transition(.opacity.animation(Motion.Anim.medium))
        .allowsHitTesting(false)
    }
  }

  private func updateSidebarVisibility(for newURLs: [URL]) {
    sidebarVisibility = newURLs.isEmpty ? .detailOnly : .all
  }

  private func handleSelectionChange(_ newURL: URL?) {
    guard let newURL else { return }
    prefetchNeighbors(around: newURL)
    isFocused = true
    imageTransform = .identity
  }

  private func ensureInitialFocus() {
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
      isFocused = true
    }
  }

  @ToolbarContentBuilder
  private var toolbarContent: some ToolbarContent {
    ToolbarItem {
      Button {
        openFileOrFolder()
      } label: {
        Label(
          "open_file_or_folder_button".localized,
          systemImage: "folder")
      }
      .help("open_file_or_folder_button".localized)
    }

    ToolbarItem {
      Button {
        refreshCurrentInputs()
      } label: {
        Label("refresh_button".localized, systemImage: "arrow.clockwise")
      }
      .disabled(currentSourceInputs.isEmpty)
      .help("refresh_button".localized)
    }

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

      ToolbarItem {
        Button {
          imageTransform.rotation = imageTransform.rotation.rotated(by: -90)
        } label: {
          Label("rotate_ccw_button".localized, systemImage: "rotate.left")
        }
        .help("rotate_ccw_button".localized)
      }

      ToolbarItem {
        Button {
          imageTransform.rotation = imageTransform.rotation.rotated(by: 90)
        } label: {
          Label("rotate_cw_button".localized, systemImage: "rotate.right")
        }
        .help("rotate_cw_button".localized)
      }

      ToolbarItem {
        Button {
          imageTransform.mirrorH.toggle()
        } label: {
          Label("mirror_horizontal_button".localized, systemImage: "arrow.left.and.right")
        }
        .help("mirror_horizontal_button".localized)
      }

      ToolbarItem {
        Button {
          imageTransform.mirrorV.toggle()
        } label: {
          Label("mirror_vertical_button".localized, systemImage: "arrow.up.and.down")
        }
        .help("mirror_vertical_button".localized)
      }

      ToolbarItem {
        Button {
          withAnimation(Motion.Anim.standard) {
            isCropping.toggle()
            if !isCropping {
              cropAspect = .freeform
            }
          }
        } label: {
          Label("crop_button".localized, systemImage: isCropping ? "crop.rotate" : "crop")
        }
        .help("crop_button".localized)
      }
    }
  }

  private func openFileOrFolder() {
    Task {
      guard let batch = await FileOpenService.openFileOrFolder() else { return }
      await MainActor.run {
        applyImageBatch(batch)
      }
    }
  }

  /// 处理拖放进窗口的文件/文件夹 URL 提供者
  private func handleDropProviders(_ providers: [NSItemProvider]) -> Bool {
    guard !providers.isEmpty else { return false }
    Task {
      if let batch = await FileOpenService.processDropProviders(providers) {
        await MainActor.run {
          applyImageBatch(batch)
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

  /// 处理裁剪结果：弹出保存面板并写入文件
  @MainActor
  private func handleCropRectPrepared(_ rect: CGRect) {
    guard let srcURL = selectedImageURL else { return }
    let panel = NSSavePanel()
    panel.canCreateDirectories = true
    panel.isExtensionHidden = false
    panel.title = "crop_save_panel_title".localized
    let ext = srcURL.pathExtension
    let base = srcURL.deletingPathExtension().lastPathComponent
    panel.nameFieldStringValue = base + "_cropped." + ext
    let res = panel.runModal()
    if res == .OK, let destURL = panel.url {
      do {
        let img = try ImageCropper.crop(url: srcURL, cropRect: rect)
        try ImageCropper.save(image: img, to: destURL)
        // 退出裁剪
        withAnimation(Motion.Anim.standard) {
          isCropping = false
          cropAspect = .freeform
        }
      } catch {
        // 简单失败提示（可扩展为 Alert）
        NSSound.beep()
      }
    }
  }
}

// MARK: - Helpers
extension ContentView {
  @MainActor
  private func applyImageBatch(_ batch: ImageBatch, preserveSelection selection: URL? = nil, previouslySelectedIndex: Int? = nil) {
    currentSourceInputs = batch.inputs
    imageURLs = batch.imageURLs

    guard !batch.imageURLs.isEmpty else {
      selectedImageURL = nil
      imageTransform = .identity
      isCropping = false
      return
    }

    if let selection, batch.imageURLs.contains(selection) {
      selectedImageURL = selection
      return
    }

    if let index = previouslySelectedIndex {
      let clamped = min(max(index, 0), batch.imageURLs.count - 1)
      selectedImageURL = batch.imageURLs[clamped]
      return
    }

    selectedImageURL = batch.imageURLs.first
  }

  @MainActor
  private func refreshCurrentInputs() {
    guard !currentSourceInputs.isEmpty else { return }
    let inputs = currentSourceInputs

    Task {
      let refreshed = await FileOpenService.discover(from: inputs, recordRecents: false)
      let batch = ImageBatch(inputs: inputs, imageURLs: refreshed)
      await MainActor.run {
        let currentSelection = selectedImageURL
        let previousIndex = currentSelection.flatMap { imageURLs.firstIndex(of: $0) }
        applyImageBatch(batch, preserveSelection: currentSelection, previouslySelectedIndex: previousIndex)
      }
    }
  }

  private func prefetchNeighbors(around url: URL) {
    guard let idx = imageURLs.firstIndex(of: url) else { return }
    var neighbors: [URL] = []
    if idx > 0 { neighbors.append(imageURLs[idx - 1]) }
    if idx + 1 < imageURLs.count { neighbors.append(imageURLs[idx + 1]) }
    // 额外：预解码较低像素的下采样图，优先速度（约 2048px）
    ImageLoader.shared.prefetch(urls: neighbors)
  }

  /// 处理键盘按键事件，实现图片切换功能
  /// 返回是否已处理，未处理则让系统/菜单接管（避免拦截快捷键）。
  private func handleKeyPress(_ press: KeyPress) -> Bool {
    guard !imageURLs.isEmpty, let currentURL = selectedImageURL else {
      // print("handleKeyPress: 图片列表为空或没有选中的图片")
      return false
    }

    let currentIndex = imageURLs.firstIndex(of: currentURL) ?? 0
    let totalCount = imageURLs.count

    // print("handleKeyPress: 按键 \(press.key), 当前索引: \(currentIndex), 总数: \(totalCount)")

    // ESC 关闭 EXIF 浮动面板
    if press.key == .escape {
      if showingExifInfo { showingExifInfo = false }
      // 保持焦点
      DispatchQueue.main.async { isFocused = true }
      return true
    }

    if let newIndex = ImageNavigation.nextIndex(
      for: press.key,
      mode: appSettings.imageNavigationKey,
      currentIndex: currentIndex,
      totalCount: totalCount
    ) {
      navigateToImage(at: newIndex)
      // 确保按键后焦点保持
      DispatchQueue.main.async { isFocused = true }
      return true
    }

    // 未处理的按键不拦截，让菜单快捷键（如 ⌥+数字）正常生效
    return false
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
