//
//  DetailView.swift
//  Pixor
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
