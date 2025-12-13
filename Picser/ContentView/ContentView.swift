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
  @State private var windowToken: Any?
  @State private var associatedWindow: NSWindow?  // ContentView对应的NSWindow实例
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
  /// 控制详情页是否展示标签编辑器
  @State var showingTagEditorPanel = false
  /// 控制标签筛选 Popover，可供侧栏与详情页共同操作
  @State private var showingFilterPopover = false
  /// 幻灯片播放状态与驱动任务
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
  // 批量删除流程状态
  @State var pendingBatchDeletionURLs: [URL] = []  // 待批量删除的图片列表
  @State var showingBatchDeletionConfirmation = false  // 是否显示批量删除确认对话框
  @State var batchDeletionProgress: Double = 0.0  // 批量删除进度（0.0 - 1.0）
  @State var isPerformingBatchDeletion = false  // 是否正在执行批量删除
  @State var batchDeletionFailedURLs: [(URL, Error)] = []  // 批量删除失败的文件列表
  @State private var filteredImageURLs: [URL] = []
  @State private var isFilteringImages = false  // 标记是否正在执行筛选任务

  // 购买解锁引导
  @State var upgradePromptContext: UpgradePromptContext?

  // 接收设置对象
  @EnvironmentObject var appSettings: AppSettings
  @EnvironmentObject var purchaseManager: PurchaseManager
  @EnvironmentObject var featureGatekeeper: FeatureGatekeeper
  @EnvironmentObject var externalOpenCoordinator: ExternalOpenCoordinator
  @EnvironmentObject var tagService: TagService

  /// 侧边栏宽度限制，防止用户将其放大全屏
  private enum LayoutMetrics {
    static let sidebarMinWidth: CGFloat = 150
    static let sidebarIdealWidth: CGFloat = 220
    static let sidebarMaxWidth: CGFloat = 360
  }

  /// 当前经过标签筛选后的图片集合，供主视图与扩展共享
  /// 根据标签筛选结果计算当前真正可见的图片列表
  var visibleImageURLs: [URL] { filteredImageURLs }

  private var filterTaskTrigger: FilterTaskTrigger {
    FilterTaskTrigger(
      urlsHash: hashForImageURLs(imageURLs),
      filter: tagService.activeFilter,
      assignmentsVersion: tagService.assignmentsVersion
    )
  }

  /// 当过滤条件导致列表为空时提供额外提示
  private var isFilterHidingAllImages: Bool {
    tagService.activeFilter.isActive && !imageURLs.isEmpty && visibleImageURLs.isEmpty
  }

  private var keyboardShortcutHandler: KeyboardShortcutHandler {
    KeyboardShortcutHandler(
      appSettings: appSettings,
      imageURLs: { visibleImageURLs },  // 快捷键始终基于筛选后的集合
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
    if let token = windowToken as? UUID {
      return token
    }
    return fallbackWindowToken
  }

  /// 幻灯片播放状态对外只读访问，避免破坏封装。
  var isSlideshowActive: Bool {
    isSlideshowPlaying
  }

  var body: some View {
    var view: AnyView = AnyView(baseContent)

    #if DEBUG

    // 调试代码：重置为“试用进行中”状态
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
          Task {
            await tagService.refreshScope(with: newURLs)
          }
          filteredImageURLs = newURLs
          // 目录切换后需要重新确保选中项在可见集合里
          ensureSelectionVisible()
          updateSidebarVisibility()
          handleSlideshowImageListChange()
        }
        .onChange(of: selectedImageURL) { _, newURL in
          handleSelectionChange(newURL)
        }
        .onChange(of: tagService.activeFilter) { _, _ in
          // 筛选条件变化时，立即标记为正在筛选，避免按钮数字闪动
          isFilteringImages = true
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
        .onChange(of: filteredImageURLs) { _, _ in
          ensureSelectionVisible()
          handleSlideshowImageListChange()
        }
        .onAppear {
          filteredImageURLs = imageURLs
          isFilteringImages = false
        }
        .task(id: filterTaskTrigger) {
          isFilteringImages = true
          filteredImageURLs = await tagService.filteredImageURLs(from: imageURLs)
          isFilteringImages = false
        }
    )

    view = AnyView(
      view
        .task {
          // 尝试消费latestBatch，只有一个ContentView会成功
          if let batch = externalOpenCoordinator.consumeLatestBatch() {
            handleExternalImageBatch(batch)
          }
        }
        .onReceive(externalOpenCoordinator.latestBatchPublisher) { batch in
          // 多个ContentView都会收到，但只有第一个能成功消费
          if let batch = externalOpenCoordinator.consumeLatestBatch() {
            handleExternalImageBatch(batch)
          }
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
        // 批量删除确认对话框
        .sheet(isPresented: $showingBatchDeletionConfirmation) {
          BatchDeletionConfirmationSheet(
            urls: pendingBatchDeletionURLs,
            onConfirm: { mode, removeOrphanTags in
              Task {
                await confirmBatchDeletion(mode: mode, removeOrphanTags: removeOrphanTags)
              }
            },
            getProgress: { batchDeletionProgress },
            isDeleting: { isPerformingBatchDeletion },
            getFailedURLs: { batchDeletionFailedURLs },
            orphanTagNames: tagService.predictOrphanTags(for: pendingBatchDeletionURLs)
          )
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
              // 保存NSWindow实例
              if let window = token as? NSWindow {
                associatedWindow = window
              }
            },
            shouldRegisterHandler: {
              // 只在有图片内容时注册键盘事件，防止空窗口干扰
              !visibleImageURLs.isEmpty
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
    SidebarView(
      imageURLs: visibleImageURLs,
      selectedImageURL: selectedImageURL,
      showingFilterPopover: $showingFilterPopover,
      onSelect: { url in
        selectedImageURL = url
      },
      onRequestBatchDeletion: { requestBatchDeletion() },
      isFilteringImages: isFilteringImages,
      onRequestUpgrade: { context in requestUpgrade(context) }
    )
    .frame(
      minWidth: LayoutMetrics.sidebarMinWidth,
      idealWidth: LayoutMetrics.sidebarIdealWidth,
      maxWidth: LayoutMetrics.sidebarMaxWidth
    )
  }

  @ViewBuilder
  private var detailColumn: some View {
    DetailView(
      imageURLs: visibleImageURLs,
      filterContext: isFilterHidingAllImages
        ? FilterEmptyContext(
          onClearFilter: { clearFilterFromDetail() },
          onShowFilters: { showingFilterPopover = true }
        )
        : nil,
      showTagEditor: showingTagEditorPanel,
      selectedImageURL: selectedImageURL,
      onOpen: openFileOrFolder,
      onNavigatePrevious: navigateToPreviousImage,
      onNavigateNext: navigateToNextImage,
      windowToken: activeWindowToken,
      showingExifInfo: $showingExifInfo,
      exifInfo: currentExifInfo,
      transform: imageTransform,
      isSlideshowActive: isSlideshowActive,
      isCropping: $isCropping,
      cropAspect: $cropAspect,
      showingAddCustomRatio: $showingAddCustomRatio
    )
    .environmentObject(appSettings)
    .environmentObject(tagService)
  }

  @ViewBuilder
  private var dropHighlightOverlay: some View {
    if isDropTargeted {
      DropOverlay()
        .transition(.opacity.animation(Motion.Anim.medium))
        .allowsHitTesting(false)
    }
  }

  private func updateSidebarVisibility() {
    sidebarVisibility = imageURLs.isEmpty ? .detailOnly : .all  // 标签筛选不影响侧边栏显隐，只看总数据源
  }

  private func clearFilterAndRestoreSelection() {
    tagService.clearFilter()
    // 清空筛选后尽量回到原始列表第一张，避免空白状态
    if let first = imageURLs.first {
      selectedImageURL = first
    } else {
      selectedImageURL = nil
    }
  }

  private func clearFilterFromDetail() {
    showingFilterPopover = false
    clearFilterAndRestoreSelection()
  }

  func ensureSelectionVisible() {
    let pool = visibleImageURLs
    guard !pool.isEmpty else {
      selectedImageURL = nil
      return
    }
    // 如果当前选中项被过滤掉，就自动跳转到新集合第一项
    if let selected = selectedImageURL {
      if !pool.contains(selected) {
        selectedImageURL = pool.first
      }
    } else {
      selectedImageURL = pool.first
    }
  }

  @MainActor
  private func navigateToPreviousImage() {
    guard let current = selectedImageURL,
          let currentIndex = visibleImageURLs.firstIndex(of: current),
          currentIndex > 0 else {
      return
    }
    selectedImageURL = visibleImageURLs[currentIndex - 1]
  }

  @MainActor
  private func navigateToNextImage() {
    guard let current = selectedImageURL,
          let currentIndex = visibleImageURLs.firstIndex(of: current),
          currentIndex < visibleImageURLs.count - 1 else {
      return
    }
    selectedImageURL = visibleImageURLs[currentIndex + 1]
  }

  // MARK: - 幻灯片播放

  /// 切换幻灯片播放/暂停，含权限校验与空集合保护
  @MainActor
  func toggleSlideshowPlayback() {
    if isSlideshowPlaying {
      stopSlideshowPlayback()
    } else {
      guard !visibleImageURLs.isEmpty else { return }
      performIfEntitled(.slideshow) {
        startSlideshowPlayback()
      }
    }
  }

  /// 启动幻灯片播放：必要时定位到第一张并拉起定时任务
  @MainActor
  private func startSlideshowPlayback() {
    guard !visibleImageURLs.isEmpty else { return }
    if selectedImageURL == nil {
      selectedImageURL = visibleImageURLs.first
    }
    isSlideshowPlaying = true
    restartSlideshowTask()
  }

  /// 停止播放并释放定时任务，保证状态一致
  @MainActor
  private func stopSlideshowPlayback() {
    slideshowTask?.cancel()
    slideshowTask = nil
    if isSlideshowPlaying {
      isSlideshowPlaying = false
    }
  }

  /// 重建定时任务，确保间隔调整或列表变化后生效
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

  /// 根据当前列表和循环策略推进下一帧，异常时自动停播
  @MainActor
  private func advanceSlideshowFrame() {
    guard isSlideshowPlaying else { return }
    guard !visibleImageURLs.isEmpty else {
      stopSlideshowPlayback()
      return
    }

    guard let current = selectedImageURL else {
      selectedImageURL = visibleImageURLs.first
      return
    }

    guard let currentIndex = visibleImageURLs.firstIndex(of: current) else {
      selectedImageURL = visibleImageURLs.first
      return
    }

    let nextIndex = currentIndex + 1
    if nextIndex < visibleImageURLs.count {
      selectedImageURL = visibleImageURLs[nextIndex]
    } else if appSettings.slideshowLoopEnabled {
      selectedImageURL = visibleImageURLs.first
    } else {
      stopSlideshowPlayback()
    }
  }

  /// 图片集合变动时同步当前选中项，并视情况重建任务
  @MainActor
  /// 图片集合或筛选变化时，校正幻灯片的播放状态
  private func handleSlideshowImageListChange() {
    let newURLs = visibleImageURLs
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

  /// 播放间隔更新后立即应用
  @MainActor
  private func handleSlideshowIntervalChange() {
    guard isSlideshowPlaying else { return }
    restartSlideshowTask()
  }

  /// 循环策略更新时评估是否需要停播
  @MainActor
  private func handleSlideshowLoopChange(_ isLooping: Bool) {
    guard isSlideshowPlaying else { return }
    if !isLooping,
       let current = selectedImageURL,
       let index = visibleImageURLs.firstIndex(of: current),
       index >= visibleImageURLs.count - 1
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

private func hashForImageURLs(_ urls: [URL]) -> Int {
  var hasher = Hasher()
  hasher.combine(urls.count)
  for url in urls {
    hasher.combine(url.standardizedFileURL.path)
  }
  return hasher.finalize()
}

private struct FilterTaskTrigger: Hashable {
  let urlsHash: Int
  let filter: TagFilter
  let assignmentsVersion: Int
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
