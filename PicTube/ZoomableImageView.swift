//
//  ZoomableImageView.swift
//  PicTube
//
//  Created by Eric Cai on 2025/8/20.
//

import AppKit
import SwiftUI

/// 纯SwiftUI实现的缩放图片视图
struct ZoomableImageView: View {
  let image: NSImage

  @EnvironmentObject var appSettings: AppSettings

  // MARK: - 缩放状态管理
  @State private var scale: CGFloat = 1.0
  @State private var lastScale: CGFloat = 1.0
  @State private var minScale: CGFloat = 0.1
  @State private var maxScale: CGFloat = 10.0

  // MARK: - 拖拽状态管理
  @State private var offset: CGSize = .zero
  @State private var lastOffset: CGSize = .zero
  @State private var isDragging: Bool = false

  // MARK: - 手势状态
  @GestureState private var magnificationState: CGFloat = 1.0
  @GestureState private var dragState: CGSize = .zero

  // MARK: - 计算属性
  // 基础适配缩放比例（使图片恰好"适配"预览区域），实际显示尺寸 = 原始尺寸 * baseFitScale * scale
  @State private var baseFitScale: CGFloat = 1.0
  private var effectiveScale: CGFloat {
    scale
  }

  private var effectiveOffset: CGSize {
    offset
  }

  var body: some View {
    GeometryReader { geometry in
      ZStack {
        // 图片内容
        Image(nsImage: image)
          .resizable()
          .aspectRatio(contentMode: .fit)
          .frame(maxWidth: .infinity, maxHeight: .infinity)
          .scaleEffect(effectiveScale)
          .offset(effectiveOffset)
          // 使用overlay添加滚轮处理
          .overlay(
            ScrollWheelHandler { deltaY in
              // 处理滚轮缩放
              let zoomFactor = 1.0 + (deltaY * appSettings.zoomSensitivity)
              let newScale = scale * zoomFactor
              let clampedScale = max(minScale, min(maxScale, newScale))

              withAnimation(.easeInOut(duration: 0.1)) {
                scale = clampedScale
                lastScale = clampedScale
              }
            }
          )
          .gesture(
            // 拖拽手势
            DragGesture()
              .onChanged { value in
                offset = CGSize(
                  width: lastOffset.width + value.translation.width,
                  height: lastOffset.height + value.translation.height
                )
              }
              .onEnded { value in
                lastOffset = offset
              }
          )
          .onTapGesture(count: 2) {
            // 双击重置缩放
            resetZoom()
          }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .onAppear {
        setupInitialState(geometry: geometry)
      }
      .onChange(of: image) { _, _ in
        // 图片变化时总是重新适应视图
        DispatchQueue.main.async {
          fitImageToView(geometry: geometry)
        }
      }
    }
    .onChange(of: appSettings.minZoomScale) { _, newValue in
      minScale = newValue
      ensureValidScale()
    }
    .onChange(of: appSettings.maxZoomScale) { _, newValue in
      maxScale = newValue
      ensureValidScale()
    }
    .onChange(of: image) { _, _ in
      // 图片变化时重置拖拽状态（缩放重置在GeometryReader内部处理）
      if appSettings.resetPanOnImageChange {
        resetPan()
      }
    }
    .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResizeNotification)) { _ in
      // 窗口大小变化时重新适应 - 需要在GeometryReader内部处理
    }
  }

  // MARK: - 私有方法

  /// 检查是否应该响应手势（修饰键检测）
  private func shouldRespondToGesture() -> Bool {
    // 如果修饰键设置为none，始终允许手势
    if appSettings.zoomModifierKey == .none {
      return true
    }

    // 否则检查是否按下了指定的修饰键
    guard let event = NSApplication.shared.currentEvent else { return false }
    return appSettings.isModifierKeyPressed(event.modifierFlags, for: appSettings.zoomModifierKey)
  }

  /// 设置初始状态
  private func setupInitialState(geometry: GeometryProxy) {
    minScale = appSettings.minZoomScale
    maxScale = appSettings.maxZoomScale
    // 延迟一帧确保视图完全布局
    DispatchQueue.main.async {
      fitImageToView(geometry: geometry)
    }
  }

  /// 处理缩放手势变化
  private func handleMagnificationChange(_ value: CGFloat) {
    // 性能优化：缩放过程中不进行复杂计算，只更新状态
    // 实际的缩放限制检查在onEnded中进行，避免频繁计算
  }

  /// 处理缩放手势结束
  private func handleMagnificationEnd(_ value: CGFloat) {
    let newScale = scale * value

    // 确保缩放比例在有效范围内
    let clampedScale = max(minScale, min(maxScale, newScale))

    // 如果缩放比例超出范围，添加动画效果
    if clampedScale != newScale {
      withAnimation(.easeInOut(duration: 0.2)) {
        scale = clampedScale
      }
    } else {
      scale = clampedScale
    }

    lastScale = scale
  }

  /// 处理拖拽手势变化
  private func handleDragChange(_ value: DragGesture.Value) {
    // 性能优化：拖拽过程中不进行边界检查，只更新状态
    // 实际的边界限制检查在onEnded中进行，避免频繁计算
  }

  /// 处理拖拽手势结束
  private func handleDragEnd(_ value: DragGesture.Value, geometry: GeometryProxy) {
    let newOffset = CGSize(
      width: offset.width + value.translation.width,
      height: offset.height + value.translation.height
    )

    // 计算拖拽边界限制
    let maxOffset = calculateMaxOffset(geometry: geometry)
    let clampedOffset = CGSize(
      width: max(-maxOffset.width, min(maxOffset.width, newOffset.width)),
      height: max(-maxOffset.height, min(maxOffset.height, newOffset.height))
    )

    withAnimation(.easeInOut(duration: 0.2)) {
      offset = clampedOffset
    }
    lastOffset = offset
  }

  /// 计算最大拖拽偏移量
  private func calculateMaxOffset(geometry: GeometryProxy) -> CGSize {
    // 根据当前缩放比例和实际视图尺寸计算最大拖拽范围
    let viewSize = geometry.size
    let imageSize = image.size

    // 使用显示尺寸参与边界计算：原始尺寸 * baseFitScale(适配) * scale(相对缩放)
    let displayedWidth = imageSize.width * baseFitScale * scale
    let displayedHeight = imageSize.height * baseFitScale * scale
    let maxOffsetX = max(0, (displayedWidth - viewSize.width) / 2)
    let maxOffsetY = max(0, (displayedHeight - viewSize.height) / 2)

    return CGSize(width: maxOffsetX, height: maxOffsetY)
  }

  /// 确保缩放比例在有效范围内
  private func ensureValidScale() {
    if scale < minScale {
      scale = minScale
    } else if scale > maxScale {
      scale = maxScale
    }
  }

  /// 重置缩放
  private func resetZoom() {
    withAnimation(.easeInOut(duration: 0.3)) {
      scale = 1.0
      lastScale = 1.0
    }
  }

  /// 重置拖拽
  private func resetPan() {
    withAnimation(.easeInOut(duration: 0.3)) {
      offset = .zero
      lastOffset = .zero
    }
  }

  /// 适应窗口大小：记录基础适配比例，并将相对缩放恢复为1（即刚好适配）
  private func fitImageToView(geometry: GeometryProxy) {
    let viewSize = geometry.size
    let imageSize = image.size

    print("FitImageToView - ViewSize: \(viewSize), ImageSize: \(imageSize)")

    guard imageSize.width > 0, imageSize.height > 0, viewSize.width > 0, viewSize.height > 0 else {
      print("FitImageToView - Invalid sizes, setting scale to 1.0")
      scale = 1.0
      lastScale = 1.0
      return
    }

    let scaleX = viewSize.width / imageSize.width
    let scaleY = viewSize.height / imageSize.height

    let fitScale = min(scaleX, scaleY)
    baseFitScale = fitScale

    print("FitImageToView - ScaleX: \(scaleX), ScaleY: \(scaleY), FitScale(base): \(fitScale)")

    withAnimation(.easeInOut(duration: 0.25)) {
      // 相对缩放设置为1.0（表示在基础适配尺寸上不额外缩放）
      scale = 1.0
      lastScale = 1.0
      offset = .zero
      lastOffset = .zero
    }
  }
}

/// 滚轮事件处理器
struct ScrollWheelHandler: NSViewRepresentable {
  let onScrollWheel: (Double) -> Void

  func makeNSView(context: Context) -> ScrollWheelView {
    let view = ScrollWheelView()
    view.onScrollWheel = onScrollWheel
    return view
  }

  func updateNSView(_ nsView: ScrollWheelView, context: Context) {
    nsView.onScrollWheel = onScrollWheel
  }
}

/// 处理滚轮事件的NSView
class ScrollWheelView: NSView {
  var onScrollWheel: ((Double) -> Void)?

  override func scrollWheel(with event: NSEvent) {
    // 使用正确方向的滚轮处理
    let deltaY = event.scrollingDeltaY
    onScrollWheel?(deltaY * 0.01)  // 移除负号，使缩放方向正确
  }

  override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
    return true
  }

  override var acceptsFirstResponder: Bool {
    return true
  }

  override func becomeFirstResponder() -> Bool {
    return true
  }
}

#Preview {
  if let testImage = NSImage(systemSymbolName: "photo", accessibilityDescription: nil) {
    ZoomableImageView(image: testImage)
      .environmentObject(AppSettings())
      .frame(width: 400, height: 300)
  } else {
    Text("无法加载测试图片")
  }
}
