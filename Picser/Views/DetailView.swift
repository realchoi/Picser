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
  let windowToken: UUID
  @Binding var showingExifInfo: Bool
  let exifInfo: ExifInfo?
  let transform: ImageTransform
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
              )
            )
              .frame(maxWidth: .infinity, maxHeight: .infinity)
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
