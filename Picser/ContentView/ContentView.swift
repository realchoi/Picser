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
  @State var alertContent: AlertContent?  // 通用弹窗内容
  @State var exifLoadTask: Task<Void, Never>? = nil
  @State var exifLoadRequestID: UUID?
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
      performDelete: { handleDeleteShortcut() }
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
      openResolvedURL: { url in openResolvedURL(url) }
    )
  }

  private var activeWindowToken: UUID {
    windowToken ?? fallbackWindowToken
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
          }
        }
        .onChange(of: showingExifInfo) { _, newValue in
          if !newValue {
            cancelOngoingExifLoad()
            currentExifInfo = nil
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

    guard let newURL else {
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
  func localized(_ key: String, fallback: String) -> String {
    let value = L10n.string(key)
    return value == key ? fallback : value
  }
}

#Preview {
  let purchaseManager = PurchaseManager()
  return ContentView()
    .environmentObject(AppSettings())
    .environmentObject(purchaseManager)
    .environmentObject(FeatureGatekeeper(purchaseManager: purchaseManager))
}
