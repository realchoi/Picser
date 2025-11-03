//
//  DetailView.swift
//
//  Extracted from ContentView to keep it lean.
//

import SwiftUI

/// 详情视图，显示选中图片及其 EXIF 信息面板。
struct DetailView: View {
  let imageURLs: [URL]
  let selectedImageURL: URL?
  let onOpen: () -> Void
  let onNavigatePrevious: () -> Void
  let onNavigateNext: () -> Void
  let windowToken: UUID
  @Binding var showingExifInfo: Bool
  let exifInfo: ExifInfo?
  let transform: ImageTransform
  let isSlideshowActive: Bool
  // 裁剪参数（由上层传入）
  @Binding var isCropping: Bool
  @Binding var cropAspect: CropAspectOption
  @Binding var showingAddCustomRatio: Bool
  @EnvironmentObject var appSettings: AppSettings

  private enum LayoutMetrics {
    static let drawerMinWidth: CGFloat = 320
    static let drawerIdealWidth: CGFloat = 360
    static let drawerMaxWidth: CGFloat = 420
  }

  var body: some View {
    GeometryReader { _ in
      Group {
        if imageURLs.isEmpty {
          EmptyHint(onOpen: onOpen)
        } else if let url = selectedImageURL {
          HStack(spacing: 0) {
            AsyncZoomableImageContainer(
              url: url,
              transform: transform,
              windowToken: windowToken,
              isCropping: isCropping,
              cropAspect: cropAspect,
              cropControls: CropControlConfiguration(
                customRatios: appSettings.customCropRatios,
                currentAspect: cropAspect,
                onSelectPreset: { preset in
          cropAspect = CropAspectOption.fromPreset(preset)
                },
                onSelectCustomRatio: { ratio in
                  cropAspect = .fixed(ratio)
                },
                onDeleteCustomRatio: { ratio in
                  if let index = appSettings.customCropRatios.firstIndex(of: ratio) {
                    appSettings.customCropRatios.remove(at: index)
                  }
                  if case .fixed(let current) = cropAspect, current == ratio {
                    cropAspect = .freeform
                  }
                },
                onAddCustomRatio: {
                  showingAddCustomRatio = true
                },
                onSave: {
                  NotificationCenter.default.post(
                    name: .cropCommitRequested,
                    object: nil,
                    userInfo: ["windowToken": windowToken]
                  )
                },
                onCancel: {
                  withAnimation(Motion.Anim.standard) {
                    isCropping = false
                    cropAspect = .freeform
                  }
                }
              ),
              isSlideshowActive: isSlideshowActive
            )
              .frame(maxWidth: .infinity, maxHeight: .infinity)
              .overlay {
                let navigationState = navigationContext
                EdgeNavigationOverlay(
                  canNavigatePrevious: navigationState.canNavigatePrevious,
                  canNavigateNext: navigationState.canNavigateNext,
                  isCropping: isCropping,
                  onNavigatePrevious: onNavigatePrevious,
                  onNavigateNext: onNavigateNext
                )
              }
              .overlay(alignment: .trailing) {
                if showingExifInfo {
                  drawerObscureOverlay
                    .transition(.opacity)
                }
              }

            if showingExifInfo {
              exifDrawer(for: exifInfo)
            }
          }
          .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
          Text(l10n: "select_image_hint")
            .font(.title)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
      }
    }
  }
}

// MARK: - EXIF 抽屉视图
private extension DetailView {
  /// 计算当前图片在导航上的可用状态，便于控制箭头按钮显隐与可点击性。
  /// - Returns: 上一张与下一张是否可达的布尔标记。
  private var navigationContext: (canNavigatePrevious: Bool, canNavigateNext: Bool) {
    guard let current = selectedImageURL, let index = imageURLs.firstIndex(of: current) else {
      return (false, false)
    }
    let hasMultiple = imageURLs.count > 1
    let canPrev = hasMultiple && index > 0
    let canNext = hasMultiple && index < imageURLs.count - 1
    return (canPrev, canNext)
  }

  private var drawerObscureOverlay: some View {
    LinearGradient(
      colors: [
        Color.black.opacity(0.18),
        Color.black.opacity(0.08),
        .clear
      ],
      startPoint: .trailing,
      endPoint: .leading
    )
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .allowsHitTesting(false)
  }

  @ViewBuilder
  func exifDrawer(for info: ExifInfo?) -> some View {
    VStack(spacing: 0) {
      if let info {
        ExifInfoView(exifInfo: info)
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else {
        ExifDrawerLoadingView()
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      }
    }
    .frame(
      minWidth: LayoutMetrics.drawerMinWidth,
      idealWidth: LayoutMetrics.drawerIdealWidth,
      maxWidth: LayoutMetrics.drawerMaxWidth
    )
    .frame(maxHeight: .infinity)
    .background(.regularMaterial)
    .overlay(alignment: .leading) {
      Divider().allowsHitTesting(false)
    }
    .transition(
      .move(edge: .trailing)
        .combined(with: .opacity)
    )
  }
}

private struct ExifDrawerLoadingView: View {

  var body: some View {
    VStack(spacing: 0) {
      header
      Divider()
      content
    }
  }

  private var header: some View {
    HStack {
      Text(l10n: "exif_window_title")
        .font(.headline)
        .foregroundColor(.primary)

      Spacer()
    }
    .padding()
  }

  private var content: some View {
    VStack(spacing: 16) {
      ProgressView()
        .progressViewStyle(.circular)
      Text(l10n: "loading_text")
        .font(.callout)
        .foregroundColor(.secondary)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    .padding(24)
  }
}

// MARK: - 边缘导航浮层
private enum EdgeNavigationLayoutMetrics {
  static let detectionWidth: CGFloat = 120
  static let buttonSize: CGFloat = 46
  static let buttonShadowRadius: CGFloat = 10
  static let animationDuration: Double = 0.2
  static let buttonEdgeInset: CGFloat = 28
}

private struct EdgeNavigationOverlay: View {
  let canNavigatePrevious: Bool
  let canNavigateNext: Bool
  let isCropping: Bool
  let onNavigatePrevious: () -> Void
  let onNavigateNext: () -> Void

  @State private var isHoveringPrevious = false
  @State private var isHoveringNext = false

  var body: some View {
    // 利用 GeometryReader 填满父级空间，以便在左右两侧布置悬浮感应区域。
    GeometryReader { geometry in
      HStack(spacing: 0) {
        edgeButtonArea(
          side: .previous,
          isHovering: $isHoveringPrevious,
          isEnabled: canNavigatePrevious && !isCropping,
          action: onNavigatePrevious
        )
        Spacer(minLength: 0)
        edgeButtonArea(
          side: .next,
          isHovering: $isHoveringNext,
          isEnabled: canNavigateNext && !isCropping,
          action: onNavigateNext
        )
      }
      .frame(width: geometry.size.width, height: geometry.size.height)
    }
    .allowsHitTesting(!isCropping && (canNavigatePrevious || canNavigateNext))
  }

  /// 构建单侧的感应区域和按钮呈现。
  private func edgeButtonArea(
    side: EdgeSide,
    isHovering: Binding<Bool>,
    isEnabled: Bool,
    action: @escaping () -> Void
  ) -> some View {
    ZStack(alignment: side == .previous ? .leading : .trailing) {
      // 透明覆盖层负责维持完整的悬停区域，即便按钮淡入淡出也不会影响底层缩放/拖拽事件。
      Color.clear
      if isHovering.wrappedValue && isEnabled {
        Button(action: action) {
          Image(systemName: side == .previous ? "chevron.left.circle.fill" : "chevron.right.circle.fill")
            .font(.system(size: EdgeNavigationLayoutMetrics.buttonSize))
            .foregroundStyle(Color.white)
            .shadow(color: .black.opacity(0.35), radius: EdgeNavigationLayoutMetrics.buttonShadowRadius, x: 0, y: 4)
        }
        .buttonStyle(.plain)
        .transition(.opacity.combined(with: .scale(scale: 0.96)))
        .animation(.easeInOut(duration: EdgeNavigationLayoutMetrics.animationDuration), value: isHovering.wrappedValue)
        .padding(side == .previous ? .leading : .trailing, EdgeNavigationLayoutMetrics.buttonEdgeInset)
      }
    }
    .frame(width: EdgeNavigationLayoutMetrics.detectionWidth)
    .frame(maxHeight: .infinity)
    .contentShape(Rectangle())
    .onHover { hovering in
      guard isEnabled else {
        if isHovering.wrappedValue {
          withAnimation(.easeInOut(duration: EdgeNavigationLayoutMetrics.animationDuration)) {
            isHovering.wrappedValue = false
          }
        }
        return
      }
      if isHovering.wrappedValue != hovering {
        withAnimation(.easeInOut(duration: EdgeNavigationLayoutMetrics.animationDuration)) {
          isHovering.wrappedValue = hovering
        }
      }
    }
    .onChange(of: isEnabled) { _, newValue in
      if !newValue && isHovering.wrappedValue {
        withAnimation(.easeInOut(duration: EdgeNavigationLayoutMetrics.animationDuration)) {
          isHovering.wrappedValue = false
        }
      }
    }
    .allowsHitTesting(isEnabled)
  }

  private enum EdgeSide {
    case previous
    case next
  }
}
