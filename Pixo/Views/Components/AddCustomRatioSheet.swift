//
//  AddCustomRatioSheet.swift
//  Pixo
//
//  Simple sheet to add a custom crop ratio (W:H) and persist it.
//

import SwiftUI

struct AddCustomRatioSheet: View {
  @EnvironmentObject var appSettings: AppSettings
  @Environment(\.dismiss) private var dismiss

  @State private var widthText: String = "1"
  @State private var heightText: String = "1"
  @State private var error: String?

  let onAdded: (CropRatio) -> Void

  init(onAdded: @escaping (CropRatio) -> Void = { _ in }) {
    self.onAdded = onAdded
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("crop_add_custom_title".localized)
        .font(.headline)

      HStack(spacing: 8) {
        TextField("W", text: $widthText)
          .textFieldStyle(.roundedBorder)
          .frame(width: 80)
        Text(":")
        TextField("H", text: $heightText)
          .textFieldStyle(.roundedBorder)
          .frame(width: 80)
      }

      if let error = error {
        Text(error)
          .font(.caption)
          .foregroundColor(.red)
      }

      HStack {
        Spacer()
        Button("cancel_button".localized) { dismiss() }
        Button("save_button".localized) { save() }
          .buttonStyle(.borderedProminent)
      }
    }
    .padding(16)
    .frame(minWidth: 300)
  }

  private func save() {
    let w = Int(widthText.trimmingCharacters(in: .whitespaces)) ?? 0
    let h = Int(heightText.trimmingCharacters(in: .whitespaces)) ?? 0
    guard w > 0, h > 0 else {
      error = "crop_add_custom_invalid".localized
      return
    }
    let r = CropRatio(width: w, height: h)
    if !appSettings.customCropRatios.contains(r) {
      appSettings.customCropRatios.append(r)
    }
    onAdded(r)
    dismiss()
  }
}

#Preview {
  AddCustomRatioSheet()
    .environmentObject(AppSettings())
}
