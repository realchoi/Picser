//
//  TrialStatusBanner.swift
//
//  Created by Eric on 2025/9/19.
//

import SwiftUI
import Combine

/// 展示试用剩余时间的提示横幅
struct TrialStatusBanner: View {
  let status: TrialStatus
  let onDismiss: () -> Void

  @State private var now: Date = Date()
  private let timer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

  var body: some View {
    HStack(alignment: .top, spacing: 12) {
      Image(systemName: "clock.badge.checkmark")
        .font(.title3)
        .foregroundStyle(.blue)

      VStack(alignment: .leading, spacing: 4) {
        Text(l10n: "trial_banner_title")
          .font(.headline)
        Text(remainingDescription)
          .font(.subheadline)
          .foregroundStyle(.secondary)
      }

      Spacer(minLength: 8)

      Button(action: onDismiss) {
        Image(systemName: "xmark.circle.fill")
          .symbolRenderingMode(.palette)
          .foregroundStyle(Color.secondary, Color.secondary.opacity(0.2))
      }
      .buttonStyle(.plain)
      .help(L10n.key("trial_banner_dismiss"))
      .accessibilityLabel(Text(l10n: "trial_banner_dismiss"))
    }
    .padding(.vertical, 12)
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
    .onReceive(timer) { value in
      now = value
    }
    .onAppear {
      now = Date()
    }
  }

  private var remainingDescription: String {
    TrialFormatter.remainingDescription(now: now, endDate: status.endDate)
  }
}
