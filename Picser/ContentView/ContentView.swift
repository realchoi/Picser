//
//  ContentView.swift
//
//  Created by Eric Cai on 2025/8/18.
//

import AppKit
import Combine
import Foundation
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
  @State private var windowToken: UUID?
  private let fallbackWindowToken = UUID()
  // 使用 @State 属性包装器来声明一个状态变量
  // 当这个变量改变时，SwiftUI 会自动刷新相关的视图
  @State var imageURLs: [URL] = []  // 文件夹中所有图片的 URL 列表
  @State var currentSourceInputs: [URL] = []  // 当前图片列表的来源 URL（文件或文件夹）
  @State var selectedImageURL: URL?  // 当前选中的图片 URL
  @State private var sidebarVisibility: NavigationSplitViewVisibility = .detailOnly  // 侧边栏可见性控制

  // EXIF 信息相关状态
  @State var showingExifInfo = false  // 是否显示 EXIF 信息弹窗
  @State var currentExifInfo: ExifInfo?  // 当前图片的 EXIF 信息
  @State var isLoadingExif = false  // 是否正在加载 EXIF 信息
  @State var isShowingExifLoadingIndicator = false  // 工具栏是否显示 EXIF 加载指示
  @State var alertContent: AlertContent?  // 通用弹窗内容
  @State var exifLoadTask: Task<Void, Never>? = nil
  @State var exifLoadRequestID: UUID?
  @State var exifLoadingIndicatorDelayTask: Task<Void, Never>? = nil
  // 拖放高亮
  @State private var isDropTargeted = false

  // 图像变换（旋转/镜像）状态（按当前选中图片临时生效）
  @State var imageTransform: ImageTransform = .identity

  // 裁剪状态
  @State var isCropping: Bool = false
  @State var cropAspect: CropAspectOption = .freeform
  @State private var showingAddCustomRatio = false
  @State private var customRatioW: String = "1"
  @State private var customRatioH: String = "1"
  @State private var isSlideshowPlaying = false
  @State private var slideshowTask: Task<Void, Never>? = nil
  @State var securityAccessGroup: SecurityScopedAccessGroup?
  @State var currentSecurityScopedInputs: [URL] = []
  @State var showingFullDiskAccessPrompt = false
  @State var pendingFullDiskAccessFileName: String?
  // 删除流程状态：记录弹窗与执行中的信息
  @State var pendingDeletionURL: URL?
  @State var showingDeletionOptions = false
  @State var isPerformingDeletion = false

  // 购买解锁引导
  @State var upgradePromptContext: UpgradePromptContext?

  // 接收设置对象
  @EnvironmentObject var appSettings: AppSettings
  @EnvironmentObject var purchaseManager: PurchaseManager
  @EnvironmentObject var featureGatekeeper: FeatureGatekeeper
  @EnvironmentObject var externalOpenCoordinator: ExternalOpenCoordinator

  /// 侧边栏宽度限制，防止用户将其放大全屏
  private enum LayoutMetrics {
    static let sidebarMinWidth: CGFloat = 150
    static let sidebarIdealWidth: CGFloat = 220
    static let sidebarMaxWidth: CGFloat = 360
  }

  private var keyboardShortcutHandler: KeyboardShortcutHandler {
    KeyboardShortcutHandler(
      appSettings: appSettings,
      imageURLs: { imageURLs },
      selectedImageURL: { selectedImageURL },
      setSelectedImage: { selectedImageURL = $0 },
      showingExifInfo: { showingExifInfo },
      setShowingExifInfo: { showingExifInfo = $0 },
      performDelete: { handleDeleteShortcut() },
      rotateCounterclockwise: { rotateCCW() },
      rotateClockwise: { rotateCW() },
      mirrorHorizontal: { mirrorHorizontal() },
      mirrorVertical: { mirrorVertical() },
      resetTransform: { resetTransform() }
    )
  }

  private var windowCommandHandlers: WindowCommandHandlers {
    WindowCommandHandlers(
      openFileOrFolder: { openFileOrFolder() },
      refresh: { refreshCurrentInputs() },
      rotateCCW: { rotateCCW() },
      rotateCW: { rotateCW() },
      mirrorHorizontal: { mirrorHorizontal() },
      mirrorVertical: { mirrorVertical() },
      resetTransform: { resetTransform() },
      navigatePrevious: { navigateToPreviousImage() },
      navigateNext: { navigateToNextImage() },
      deleteSelection: { _ = handleDeleteShortcut() },
      openResolvedURL: { url in openResolvedURL(url) }
    )
  }

  private var activeWindowToken: UUID {
    windowToken ?? fallbackWindowToken
  }

  /// 幻灯片播放状态对外只读访问，避免破坏封装。
  var isSlideshowActive: Bool {
    isSlideshowPlaying
  }

  var body: some View {
    var view: AnyView = AnyView(baseContent)

    #if DEBUG

    // // 调试代码：重置为“试用进行中”状态
    // view = AnyView(
    //   view
    //     .onAppear(perform: {
    //       purchaseManager.resetLocalState()
    //     })
    // )

    // 调试代码：重置为“试用过期”状态
    // view = AnyView(
    //   view
    //     .onAppear(perform: {
    //       purchaseManager.simulateTrialExpiration()
    //     })
    // )

    #endif

    view = AnyView(
      view.onDrop(of: [UTType.fileURL], isTargeted: $isDropTargeted) { providers in
        handleDropProviders(providers)
      }
    )

    view = AnyView(
      view.safeAreaInset(edge: .bottom, spacing: 0) {
        trialBannerInset
      }
    )

    view = AnyView(
      view
        .animation(.easeInOut(duration: 0.25), value: purchaseManager.state)
        .animation(.easeInOut(duration: 0.25), value: purchaseManager.isTrialBannerDismissed)
    )

    view = AnyView(
      view
        .onChange(of: imageURLs) { _, newURLs in
          updateSidebarVisibility(for: newURLs)
          handleSlideshowImageListChange(newURLs)
        }
        .onChange(of: selectedImageURL) { _, newURL in
          handleSelectionChange(newURL)
        }
        .onChange(of: purchaseManager.state) { _, _ in
          if !purchaseManager.isEntitled {
            withAnimation(Motion.Anim.standard) {
              isCropping = false
            }
            showingAddCustomRatio = false
            if isSlideshowPlaying {
              stopSlideshowPlayback()
            }
          }
        }
        .onChange(of: showingExifInfo) { _, newValue in
          if !newValue {
            cancelOngoingExifLoad()
            currentExifInfo = nil
          }
        }
        .onChange(of: appSettings.slideshowIntervalSeconds) { _, _ in
          handleSlideshowIntervalChange()
        }
        .onChange(of: appSettings.slideshowLoopEnabled) { _, newValue in
          handleSlideshowLoopChange(newValue)
        }
        .onChange(of: isCropping) { _, newValue in
          if newValue {
            stopSlideshowPlayback()
          }
        }
    )

    view = AnyView(
      view
        .task {
          if let batch = externalOpenCoordinator.consumeLatestBatch() {
            handleExternalImageBatch(batch)
          }
        }
        .onReceive(externalOpenCoordinator.latestBatchPublisher) { batch in
          handleExternalImageBatch(batch)
          externalOpenCoordinator.clearLatestBatch()
        }
    )

    view = AnyView(
      view
        .sheet(isPresented: $showingAddCustomRatio) {
          AddCustomRatioSheet { ratio in
            if !isCropping {
              isCropping = true
            }
            cropAspect = .fixed(ratio)
          }
          .environmentObject(appSettings)
        }
    )

    view = AnyView(
      view
        .onReceive(NotificationCenter.default.publisher(for: .cropRectPrepared)) { notif in
          guard let token = notif.userInfo?["windowToken"] as? UUID, token == activeWindowToken else { return }
          if let rectVal = notif.userInfo?["rect"] as? NSValue {
            handleCropRectPrepared(rectVal.rectValue)
          }
        }
    )

    view = AnyView(
      view
        .toolbar { toolbarContent }
        // 删除确认对话框：提示选择移动到废纸篓或直接删除
        .confirmationDialog(
          L10n.string("delete_dialog_title"),
          isPresented: $showingDeletionOptions,
          presenting: pendingDeletionURL
        ) { url in
          Button(L10n.key("delete_move_to_trash_button"), role: .destructive) {
            confirmDeletion(of: url, mode: .moveToTrash)
          }
          Button(L10n.key("delete_permanent_button"), role: .destructive) {
            confirmDeletion(of: url, mode: .deletePermanently)
          }
          Button(L10n.key("cancel_button"), role: .cancel) {
            cancelDeletionRequest()
          }
        } message: { url in
          Text(String(format: L10n.string("delete_dialog_message"), url.lastPathComponent))
        }
        .alert(
          L10n.string("delete_permission_title"),
          isPresented: $showingFullDiskAccessPrompt,
          presenting: pendingFullDiskAccessFileName
        ) { fileName in
          Button(L10n.key("delete_permission_open_button")) {
            FullDiskAccessChecker.openSettings()
            pendingFullDiskAccessFileName = nil
          }
          Button(L10n.key("cancel_button"), role: .cancel) {
            pendingFullDiskAccessFileName = nil
          }
        } message: { fileName in
          Text(String(format: L10n.string("delete_permission_message"), fileName))
        }
        .alert(item: $alertContent) { alertData in
          Alert(
            title: Text(alertData.title),
            message: Text(alertData.message),
            dismissButton: .default(Text(l10n: "ok_button"))
          )
        }
    )

    view = AnyView(
      view
        .background(
          KeyboardShortcutBridge(
            handlerProvider: {
              { event in
                keyboardShortcutHandler.handle(event: event)
              }
            },
            tokenUpdate: { token in
              windowToken = token
            }
          )
        )
    )

    view = AnyView(
      view
        .focusedSceneValue(\.windowCommandHandlers, windowCommandHandlers)
        .onDisappear {
          stopSlideshowPlayback()
        }
    )

    return view
  }

  private var baseContent: some View {
    ZStack {
      navigationLayout
      dropHighlightOverlay
    }
  }

  @ViewBuilder
  private var navigationLayout: some View {
    NavigationSplitView(columnVisibility: $sidebarVisibility) {
      sidebarColumn
        .navigationSplitViewColumnWidth(
          min: LayoutMetrics.sidebarMinWidth,
          ideal: LayoutMetrics.sidebarIdealWidth,
          max: LayoutMetrics.sidebarMaxWidth
        )
    } detail: {
      detailColumn
    }
    .background(
      SplitViewWidthLimiter(
        minWidth: LayoutMetrics.sidebarMinWidth,
        maxWidth: LayoutMetrics.sidebarMaxWidth
      )
      .allowsHitTesting(false)
    )
  }

  @ViewBuilder
  private var sidebarColumn: some View {
    SidebarView(imageURLs: imageURLs, selectedImageURL: selectedImageURL) { url in
      selectedImageURL = url
    }
    .frame(
      minWidth: LayoutMetrics.sidebarMinWidth,
      idealWidth: LayoutMetrics.sidebarIdealWidth,
      maxWidth: LayoutMetrics.sidebarMaxWidth
    )
  }

  @ViewBuilder
  private var detailColumn: some View {
    DetailView(
      imageURLs: imageURLs,
      selectedImageURL: selectedImageURL,
      onOpen: openFileOrFolder,
      onNavigatePrevious: navigateToPreviousImage,
      onNavigateNext: navigateToNextImage,
      windowToken: activeWindowToken,
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

  @MainActor
  private func navigateToPreviousImage() {
    guard let current = selectedImageURL,
          let currentIndex = imageURLs.firstIndex(of: current),
          currentIndex > 0 else {
      return
    }
    selectedImageURL = imageURLs[currentIndex - 1]
  }

  @MainActor
  private func navigateToNextImage() {
    guard let current = selectedImageURL,
          let currentIndex = imageURLs.firstIndex(of: current),
          currentIndex < imageURLs.count - 1 else {
      return
    }
    selectedImageURL = imageURLs[currentIndex + 1]
  }

  // MARK: - 幻灯片播放

  @MainActor
  func toggleSlideshowPlayback() {
    if isSlideshowPlaying {
      stopSlideshowPlayback()
    } else {
      guard !imageURLs.isEmpty else { return }
      performIfEntitled(.slideshow) {
        startSlideshowPlayback()
      }
    }
  }

  @MainActor
  private func startSlideshowPlayback() {
    guard !imageURLs.isEmpty else { return }
    if selectedImageURL == nil {
      selectedImageURL = imageURLs.first
    }
    isSlideshowPlaying = true
    restartSlideshowTask()
  }

  @MainActor
  private func stopSlideshowPlayback() {
    slideshowTask?.cancel()
    slideshowTask = nil
    if isSlideshowPlaying {
      isSlideshowPlaying = false
    }
  }

  @MainActor
  private func restartSlideshowTask() {
    slideshowTask?.cancel()
    guard isSlideshowPlaying else { return }
    slideshowTask = Task { @MainActor in
      while !Task.isCancelled {
        let intervalSeconds = max(appSettings.slideshowIntervalSeconds, 0.1)
        let nanoseconds = UInt64(intervalSeconds * 1_000_000_000)
        do {
          try await Task.sleep(nanoseconds: nanoseconds)
        } catch {
          break
        }
        guard !Task.isCancelled, isSlideshowPlaying else { continue }
        advanceSlideshowFrame()
      }
    }
  }

  @MainActor
  private func advanceSlideshowFrame() {
    guard isSlideshowPlaying else { return }
    guard !imageURLs.isEmpty else {
      stopSlideshowPlayback()
      return
    }

    guard let current = selectedImageURL else {
      selectedImageURL = imageURLs.first
      return
    }

    guard let currentIndex = imageURLs.firstIndex(of: current) else {
      selectedImageURL = imageURLs.first
      return
    }

    let nextIndex = currentIndex + 1
    if nextIndex < imageURLs.count {
      selectedImageURL = imageURLs[nextIndex]
    } else if appSettings.slideshowLoopEnabled {
      selectedImageURL = imageURLs.first
    } else {
      stopSlideshowPlayback()
    }
  }

  @MainActor
  private func handleSlideshowImageListChange(_ newURLs: [URL]) {
    if newURLs.isEmpty {
      stopSlideshowPlayback()
      return
    }
    guard isSlideshowPlaying else { return }

    if let current = selectedImageURL {
      if !newURLs.contains(current) {
        selectedImageURL = newURLs.first
      }
    } else {
      selectedImageURL = newURLs.first
    }

    if newURLs.count <= 1 && !appSettings.slideshowLoopEnabled {
      stopSlideshowPlayback()
      return
    }
    restartSlideshowTask()
  }

  @MainActor
  private func handleSlideshowIntervalChange() {
    guard isSlideshowPlaying else { return }
    restartSlideshowTask()
  }

  @MainActor
  private func handleSlideshowLoopChange(_ isLooping: Bool) {
    guard isSlideshowPlaying else { return }
    if !isLooping,
       let current = selectedImageURL,
       let index = imageURLs.firstIndex(of: current),
       index >= imageURLs.count - 1
    {
      stopSlideshowPlayback()
    }
  }

  @MainActor
  private func handleDeleteShortcut() -> Bool {
    guard selectedImageURL != nil, !isPerformingDeletion else { return false }
    requestDeletion()
    return true
  }

  @MainActor
  private func handleSelectionChange(_ newURL: URL?) {
    // 切换图片时关闭遗留的删除弹窗，避免误操作
    if showingDeletionOptions {
      cancelDeletionRequest()
    }

    if isCropping {
      withAnimation(Motion.Anim.standard) {
        isCropping = false
        cropAspect = .freeform
      }
      showingAddCustomRatio = false
    }

    guard let newURL else {
      if isSlideshowPlaying {
        stopSlideshowPlayback()
      }
      imageTransform = .identity
      if showingExifInfo {
        withAnimation(Motion.Anim.drawer) {
          showingExifInfo = false
        }
      }
      currentExifInfo = nil
      cancelOngoingExifLoad()
      return
    }
    prefetchNeighbors(around: newURL)
    imageTransform = .identity

    if showingExifInfo {
      currentExifInfo = nil
      startExifLoad(for: newURL, shouldPresentPanel: false)
    } else {
      cancelOngoingExifLoad()
      currentExifInfo = nil
    }
  }

  func openFileOrFolder() {
    Task {
      guard let batch = await FileOpenService.openFileOrFolder(recursive: appSettings.imageScanRecursively) else { return }
      await MainActor.run {
        applyImageBatch(batch)
      }
    }
  }

  /// 处理拖放进窗口的文件/文件夹 URL 提供者
  private func handleDropProviders(_ providers: [NSItemProvider]) -> Bool {
    guard !providers.isEmpty else { return false }
    Task {
      if let batch = await FileOpenService.processDropProviders(providers, recursive: appSettings.imageScanRecursively) {
        await MainActor.run {
          applyImageBatch(batch)
        }
      }
    }
    return true
  }

  // computeImageURLs moved to ImageDiscovery

}

// MARK: - Helpers
extension ContentView {
  func localized(_ key: String) -> String {
    L10n.string(key)
  }
}

#Preview {
  let purchaseManager = PurchaseManager()
  return ContentView()
    .environmentObject(AppSettings())
    .environmentObject(purchaseManager)
    .environmentObject(FeatureGatekeeper(purchaseManager: purchaseManager))
}
