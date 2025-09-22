//
//  TrialExpiredBanner.swift
//  Pixor
//
//  Created by Eric Cai on 2025/09/19.
//

import SwiftUI

/// 试用结束后的升级提示横幅
struct TrialExpiredBanner: View {
  let onPurchase: () -> Void
  let onRestore: () -> Void
  let onDismiss: () -> Void

  var body: some View {
    HStack(alignment: .center, spacing: 16) {
      Image(systemName: "lock.circle")
        .font(.title2)
        .foregroundStyle(.orange)

      VStack(alignment: .leading, spacing: 4) {
        Text("trial_expired_title".localized)
          .font(.headline)
        Text("trial_expired_subtitle".localized)
          .font(.subheadline)
          .foregroundStyle(.secondary)
      }

      Spacer(minLength: 12)

      HStack(spacing: 8) {
        Button("purchase_section_restore".localized, action: onRestore)
          .buttonStyle(.bordered)

        Button("purchase_section_purchase".localized, action: onPurchase)
          .buttonStyle(.borderedProminent)
      }

      Button(action: onDismiss) {
        Image(systemName: "xmark")
          .font(.subheadline)
          .foregroundStyle(.secondary)
      }
      .buttonStyle(.plain)
      .help("trial_expired_dismiss".localized)
    }
    .padding(.vertical, 14)
    .padding(.horizontal, 16)
    .background(
      .thinMaterial,
      in: RoundedRectangle(cornerRadius: 16, style: .continuous)
    )
    .overlay(
      RoundedRectangle(cornerRadius: 16, style: .continuous)
        .stroke(Color.primary.opacity(0.12), lineWidth: 1)
    )
    .shadow(color: .black.opacity(0.08), radius: 16, x: 0, y: 8)
  }
}
