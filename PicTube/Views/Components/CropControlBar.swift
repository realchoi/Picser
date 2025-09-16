//
//  CropControlBar.swift
//  PicTube
//
//  Lightweight overlay controls shown during cropping.
//

import SwiftUI

struct CropControlConfiguration {
  var customRatios: [CropRatio]
  var currentAspect: CropAspectOption
  let onSelectPreset: (CropPreset) -> Void
  let onSelectCustomRatio: (CropRatio) -> Void
  let onAddCustomRatio: () -> Void
  let onSave: () -> Void
  let onCancel: () -> Void
}

struct CropControlBar: View {
  let config: CropControlConfiguration

  var body: some View {
    HStack(spacing: 14) {
      aspectMenu
      Divider()
        .frame(height: 24)
      Button(action: config.onSave) {
        Label("crop_save_button".localized, systemImage: "square.and.arrow.down")
      }
      .buttonStyle(.borderedProminent)
      Button(action: config.onCancel) {
        Label("crop_cancel_button".localized, systemImage: "xmark.circle")
      }
      .buttonStyle(.bordered)
    }
    .padding(.horizontal, 18)
    .padding(.vertical, 12)
    .background(.regularMaterial)
    .clipShape(Capsule())
    .shadow(color: Color.black.opacity(0.2), radius: 18, x: 0, y: 10)
  }

  private var aspectMenu: some View {
    Menu {
      ForEach(CropPreset.allCases, id: \.id) { preset in
        Button {
          config.onSelectPreset(preset)
        } label: {
          menuLabel(text: preset.titleKey.localized, isSelected: isPresetSelected(preset))
        }
      }

      if !config.customRatios.isEmpty {
        Divider()
        ForEach(config.customRatios, id: \.id) { ratio in
          Button {
            config.onSelectCustomRatio(ratio)
          } label: {
            menuLabel(text: ratio.displayName, isSelected: isCustomSelected(ratio))
          }
        }
      }

      Divider()
      Button(action: config.onAddCustomRatio) {
        Label("crop_add_custom".localized, systemImage: "plus")
      }
    } label: {
      Label(currentSelectionTitle(), systemImage: "aspectratio")
        .labelStyle(.titleAndIcon)
    }
    .menuStyle(.borderedButton)
  }

  private func menuLabel(text: String, isSelected: Bool) -> some View {
    HStack {
      if isSelected {
        Image(systemName: "checkmark")
      }
      Text(text)
    }
  }

  private func isPresetSelected(_ preset: CropPreset) -> Bool {
    switch (preset, config.currentAspect) {
    case (.freeform, .freeform): return true
    case (.original, .original): return true
    default:
      if let ratio = preset.fixedRatio, case .fixed(let current) = config.currentAspect {
        return current == ratio
      }
      return false
    }
  }

  private func isCustomSelected(_ ratio: CropRatio) -> Bool {
    if case .fixed(let current) = config.currentAspect {
      return current == ratio
    }
    return false
  }

  private func currentSelectionTitle() -> String {
    switch config.currentAspect {
    case .freeform:
      return "crop_ratio_freeform".localized
    case .original:
      return "crop_ratio_original".localized
    case .fixed(let ratio):
      return ratio.displayName
    }
  }
}

// 读取 View 尺寸的简易辅助
private struct SizeReaderModifier: ViewModifier {
  @Binding var size: CGSize

  func body(content: Content) -> some View {
    content
      .background(
        GeometryReader { proxy in
          Color.clear
            .onAppear { size = proxy.size }
            .onChange(of: proxy.size) { _, newSize in size = newSize }
        }
      )
  }
}

extension View {
  func readSize(into binding: Binding<CGSize>) -> some View {
    self.modifier(SizeReaderModifier(size: binding))
  }
}
