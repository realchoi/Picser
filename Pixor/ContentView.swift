//
//  ContentView.swift
//  Pixor
//
//  Created by Eric Cai on 2025/8/18.
//

import AppKit
import Foundation
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
  @State private var windowToken: UUID?
  private let fallbackWindowToken = UUID()
  // 使用 @State 属性包装器来声明一个状态变量
  // 当这个变量改变时，SwiftUI 会自动刷新相关的视图
  @State private var imageURLs: [URL] = []  // 文件夹中所有图片的 URL 列表
  @State private var currentSourceInputs: [URL] = []  // 当前图片列表的来源 URL（文件或文件夹）
  @State private var selectedImageURL: URL?  // 当前选中的图片 URL
  @State private var sidebarVisibility: NavigationSplitViewVisibility = .detailOnly  // 侧边栏可见性控制

  // EXIF 信息相关状态
  @State private var showingExifInfo = false  // 是否显示 EXIF 信息弹窗
  @State private var currentExifInfo: ExifInfo?  // 当前图片的 EXIF 信息
  @State private var isLoadingExif = false  // 是否正在加载 EXIF 信息
  @State private var alertContent: AlertContent?  // 通用弹窗内容
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
  @State private var securityAccess: SecurityScopedAccess?

  // 购买解锁引导
  @State var upgradePromptContext: UpgradePromptContext?

  // 接收设置对象
  @EnvironmentObject var appSettings: AppSettings
  @EnvironmentObject var purchaseManager: PurchaseManager

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
      setShowingExifInfo: { showingExifInfo = $0 }
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
        .sheet(item: $upgradePromptContext) { context in
          PurchaseInfoView(
            context: context,
            onPurchase: { kind in
              upgradePromptContext = nil
              startPurchaseFlow(kind: kind)
            },
            onRestore: {
              upgradePromptContext = nil
              startRestoreFlow()
            }
          )
          .environmentObject(purchaseManager)
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
        .alert(item: $alertContent) { alertData in
          Alert(
            title: Text(alertData.title),
            message: Text(alertData.message),
            dismissButton: .default(Text("ok_button".localized))
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

  @ViewBuilder
  private var trialBannerInset: some View {
    if purchaseManager.isTrialBannerDismissed {
      EmptyView()
    } else {
      switch purchaseManager.state {
      case let .trial(status):
        bannerContainer {
          TrialStatusBanner(status: status) {
            withAnimation { purchaseManager.dismissTrialBanner() }
          }
        }
      case .trialExpired(_):
        bannerContainer {
          TrialExpiredBanner(
            title: localized("trial_expired_title", fallback: "试用已结束"),
            message: localized("trial_expired_subtitle", fallback: "试用已结束，请升级解锁全部功能。"),
            onPurchase: { requestUpgrade(.purchase) },
            onRestore: { startRestoreFlow() },
            onDismiss: {
              withAnimation { purchaseManager.dismissTrialBanner() }
            }
          )
        }
      case .subscriberLapsed(_):
        let fallbackTitle = "订阅已到期"
        let fallbackMessage = "订阅已到期，请续订或恢复购买以继续使用高级功能。"
        bannerContainer {
          TrialExpiredBanner(
            title: localized("subscription_lapsed_title", fallback: fallbackTitle),
            message: localized("subscription_lapsed_subtitle", fallback: fallbackMessage),
            onPurchase: { requestUpgrade(.purchase) },
            onRestore: { startRestoreFlow() },
            onDismiss: {
              withAnimation { purchaseManager.dismissTrialBanner() }
            }
          )
        }
      case .revoked:
        let fallbackTitle = "权限已撤销"
        let fallbackMessage = "检测到账户存在异常，已暂时停用高级功能，请尝试恢复购买或联系支持。"
        bannerContainer {
          TrialExpiredBanner(
            title: localized("purchase_revoked_title", fallback: fallbackTitle),
            message: localized("purchase_revoked_subtitle", fallback: fallbackMessage),
            onPurchase: { requestUpgrade(.purchase) },
            onRestore: { startRestoreFlow() },
            onDismiss: {
              withAnimation { purchaseManager.dismissTrialBanner() }
            }
          )
        }
      case .subscriber, .lifetime:
        EmptyView()
      case .onboarding, .unknown:
        EmptyView()
      }
    }
  }

  @ViewBuilder
  private func bannerContainer<Content: View>(@ViewBuilder content: () -> Content) -> some View {
    HStack {
      Spacer()
      content()
        .frame(maxWidth: 520)
      Spacer()
    }
    .padding(.horizontal, 16)
    .padding(.bottom, 20)
    .transition(.move(edge: .bottom).combined(with: .opacity))
  }

  private func updateSidebarVisibility(for newURLs: [URL]) {
    sidebarVisibility = newURLs.isEmpty ? .detailOnly : .all
  }

  private func handleSelectionChange(_ newURL: URL?) {
    guard let newURL else { return }
    prefetchNeighbors(around: newURL)
    imageTransform = .identity
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
          rotateCCW()
        } label: {
          Label("rotate_ccw_button".localized, systemImage: "rotate.left")
        }
        .help("rotate_ccw_button".localized)
      }

      ToolbarItem {
        Button {
          rotateCW()
        } label: {
          Label("rotate_cw_button".localized, systemImage: "rotate.right")
        }
        .help("rotate_cw_button".localized)
      }

      ToolbarItem {
        Button {
          mirrorHorizontal()
        } label: {
          Label("mirror_horizontal_button".localized, systemImage: "arrow.left.and.right")
        }
        .help("mirror_horizontal_button".localized)
      }

      ToolbarItem {
        Button {
          mirrorVertical()
        } label: {
          Label("mirror_vertical_button".localized, systemImage: "arrow.up.and.down")
        }
        .help("mirror_vertical_button".localized)
      }

      ToolbarItem {
        Button {
          performIfEntitled(.crop) {
            withAnimation(Motion.Anim.standard) {
              isCropping.toggle()
              if !isCropping {
                cropAspect = .freeform
              }
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
        updateSecurityAccess(using: batch.inputs)
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
          updateSecurityAccess(using: batch.inputs)
          applyImageBatch(batch)
        }
      }
    }
    return true
  }

  /// 显示图片的 exif 信息
  private func showExifInfo() {
    guard let currentURL = selectedImageURL else {
      alertContent = AlertContent(
        title: "exif_loading_error_title".localized,
        message: "exif_no_image_selected".localized
      )
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
          self.alertContent = AlertContent(
            title: "exif_loading_error_title".localized,
            message: "exif_file_read_error".localized
          )
        }
      } catch ExifExtractionError.failedToExtractProperties {
        await MainActor.run {
          self.isLoadingExif = false
          self.alertContent = AlertContent(
            title: "exif_loading_error_title".localized,
            message: "exif_metadata_extract_error".localized
          )
        }
      } catch {
        await MainActor.run {
          self.isLoadingExif = false
          // 使用本地化的通用错误提示
          self.alertContent = AlertContent(
            title: "exif_loading_error_title".localized,
            message: "exif_unexpected_error".localized
          )
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
  func presentAlert(_ content: AlertContent) {
    alertContent = content
  }

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

  private func rotateCCW() {
    performIfEntitled(.transform) {
      imageTransform.rotation = imageTransform.rotation.rotated(by: -90)
    }
  }

  private func rotateCW() {
    performIfEntitled(.transform) {
      imageTransform.rotation = imageTransform.rotation.rotated(by: 90)
    }
  }

  private func mirrorHorizontal() {
    performIfEntitled(.transform) {
      imageTransform.mirrorH.toggle()
    }
  }

  private func mirrorVertical() {
    performIfEntitled(.transform) {
      imageTransform.mirrorV.toggle()
    }
  }

  private func resetTransform() {
    imageTransform = .identity
  }

  private func openResolvedURL(_ url: URL) {
    Task {
      let directory = url.hasDirectoryPath ? url : url.deletingLastPathComponent()
      let access = SecurityScopedAccess(url: directory)
      let normalized = [directory.standardizedFileURL]
      let uniqueSorted = await FileOpenService.discover(from: normalized, recordRecents: false)
      let batch = ImageBatch(inputs: normalized, imageURLs: uniqueSorted)
      await MainActor.run {
        securityAccess = access
        applyImageBatch(batch)
      }
    }
  }

  private func updateSecurityAccess(using inputs: [URL]) {
    guard let first = inputs.first else {
      securityAccess = nil
      return
    }
    let directory = first.hasDirectoryPath ? first : first.deletingLastPathComponent()
    securityAccess = SecurityScopedAccess(url: directory)
  }

  private func localized(_ key: String, fallback: String) -> String {
    let value = key.localized
    return value == key ? fallback : value
  }

}

#Preview {
  ContentView()
    .environmentObject(AppSettings())
    .environmentObject(PurchaseManager())
}

private final class SecurityScopedAccess {
  private let url: URL
  private let didStart: Bool

  init(url: URL) {
    self.url = url
    self.didStart = url.startAccessingSecurityScopedResource()
  }

  deinit {
    if didStart {
      url.stopAccessingSecurityScopedResource()
    }
  }
}
