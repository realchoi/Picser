//
//  CropControlBar.swift
//  Pixor
//
//  Lightweight overlay controls shown during cropping.
//

import SwiftUI

struct CropControlConfiguration {
  var customRatios: [CropRatio]
  var currentAspect: CropAspectOption
  let onSelectPreset: (CropPreset) -> Void
  let onSelectCustomRatio: (CropRatio) -> Void
  let onDeleteCustomRatio: (CropRatio) -> Void
  let onAddCustomRatio: () -> Void
  let onSave: () -> Void
  let onCancel: () -> Void
}

struct CropControlBar: View {
  let config: CropControlConfiguration
  @State private var isAspectPickerPresented = false

  var body: some View {
    HStack(spacing: 14) {
      aspectPicker
      Divider()
        .frame(height: 24)
      Button(action: config.onSave) {
        Label(L10n.key("crop_save_button"), systemImage: "square.and.arrow.down")
      }
      .buttonStyle(.borderedProminent)
      Button(action: config.onCancel) {
        Label(L10n.key("crop_cancel_button"), systemImage: "xmark.circle")
      }
      .buttonStyle(.bordered)
    }
    .padding(.horizontal, 18)
    .padding(.vertical, 12)
    .background(.regularMaterial)
    .clipShape(Capsule())
    .shadow(color: Color.black.opacity(0.2), radius: 18, x: 0, y: 10)
  }

  private var aspectPicker: some View {
    Button {
      isAspectPickerPresented.toggle()
    } label: {
      Label(currentSelectionTitle(), systemImage: "aspectratio")
        .labelStyle(.titleAndIcon)
    }
    .buttonStyle(.bordered)
    .popover(isPresented: $isAspectPickerPresented, arrowEdge: .bottom) {
      AspectPickerView(
        config: config,
        dismiss: { isAspectPickerPresented = false }
      )
    }
  }

  private func currentSelectionTitle() -> String {
    switch config.currentAspect {
    case .freeform:
      return L10n.string("crop_ratio_freeform")
    case .original:
      return L10n.string("crop_ratio_original")
    case .fixed(let ratio):
      return ratio.displayName
    }
  }
}

private struct AspectPickerView: View {
  let config: CropControlConfiguration
  let dismiss: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      ScrollView {
        VStack(alignment: .leading, spacing: 10) {
          VStack(alignment: .leading, spacing: 6) {
            ForEach(CropPreset.allCases, id: \.id) { preset in
              AspectOptionRow(
                title: L10n.string(preset.titleKey),
                isSelected: isPresetSelected(preset),
                onSelect: {
                  config.onSelectPreset(preset)
                  dismiss()
                }
              )
            }
          }

          if !config.customRatios.isEmpty {
            Divider()
            VStack(alignment: .leading, spacing: 6) {
              Text(l10n: "crop_custom_group")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)

              ForEach(config.customRatios, id: \.id) { ratio in
                CustomRatioRow(
                  ratio: ratio,
                  isSelected: isCustomSelected(ratio),
                  onSelect: {
                    config.onSelectCustomRatio(ratio)
                    dismiss()
                  },
                  onDelete: {
                    config.onDeleteCustomRatio(ratio)
                  }
                )
              }
            }
          }
        }
        .padding(.vertical, 6)
      }
      .frame(maxHeight: 280)

      Divider()

      Button {
        dismiss()
        config.onAddCustomRatio()
      } label: {
        Label(L10n.key("crop_add_custom"), systemImage: "plus")
          .frame(maxWidth: .infinity, alignment: .leading)
      }
      .buttonStyle(.borderless)
    }
    .padding(16)
    .frame(width: 260)
  }

  private func isPresetSelected(_ preset: CropPreset) -> Bool {
    switch (preset, config.currentAspect) {
    case (.freeform, .freeform):
      return true
    case (.original, .original):
      return true
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
}

private struct AspectOptionRow: View {
  let title: String
  let isSelected: Bool
  let onSelect: () -> Void

  var body: some View {
    Button(action: onSelect) {
      HStack(spacing: 8) {
        Text(title)
          .font(.body)
          .foregroundColor(.primary)
          .lineLimit(1)
          .layoutPriority(1)
        Spacer(minLength: 8)
        if isSelected {
          Image(systemName: "checkmark")
            .font(.system(size: 12, weight: .semibold))
            .foregroundColor(.accentColor)
        }
      }
      .padding(.horizontal, 12)
      .padding(.vertical, 6)
      .background(
        RoundedRectangle(cornerRadius: 8)
          .fill(isSelected ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.12))
      )
      .overlay(
        RoundedRectangle(cornerRadius: 8)
          .stroke(isSelected ? Color.accentColor : Color.secondary.opacity(0.35), lineWidth: 1)
      )
    }
    .buttonStyle(.plain)
  }
}

private struct CustomRatioRow: View {
  let ratio: CropRatio
  let isSelected: Bool
  let onSelect: () -> Void
  let onDelete: () -> Void

  var body: some View {
    HStack(spacing: 10) {
      Text(ratio.displayName)
        .font(.body)
        .foregroundColor(isSelected ? Color.accentColor : Color.primary)
        .lineLimit(1)
        .layoutPriority(1)
      Spacer(minLength: 8)
      Button(action: onDelete) {
        Image(systemName: "trash")
          .font(.system(size: 13, weight: .semibold))
      }
      .buttonStyle(.plain)
      .foregroundColor(.red)
      .help(L10n.key("crop_custom_delete_help"))
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 6)
    .background(
      RoundedRectangle(cornerRadius: 8)
        .fill(isSelected ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.12))
    )
    .overlay(
      RoundedRectangle(cornerRadius: 8)
        .stroke(isSelected ? Color.accentColor : Color.secondary.opacity(0.35), lineWidth: 1)
    )
    .contentShape(RoundedRectangle(cornerRadius: 8))
    .onTapGesture(perform: onSelect)
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
