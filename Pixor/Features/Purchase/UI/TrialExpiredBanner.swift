//
//  TrialExpiredBanner.swift
//  Pixor
//
//  Created by Eric Cai on 2025/09/19.
//

import SwiftUI

/// 试用结束后的升级提示横幅
struct TrialExpiredBanner: View {
  let title: String
  let message: String
  let onPurchase: () -> Void
  let onRestore: () -> Void
  let onDismiss: () -> Void

  init(
    title: String = L10n.string("trial_expired_title"),
    message: String = L10n.string("trial_expired_subtitle"),
    onPurchase: @escaping () -> Void,
    onRestore: @escaping () -> Void,
    onDismiss: @escaping () -> Void
  ) {
    self.title = title
    self.message = message
    self.onPurchase = onPurchase
    self.onRestore = onRestore
    self.onDismiss = onDismiss
  }

  var body: some View {
    HStack(alignment: .center, spacing: 16) {
      Image(systemName: "lock.circle")
        .font(.title2)
        .foregroundStyle(.orange)

      VStack(alignment: .leading, spacing: 4) {
        Text(title)
          .font(.headline)
        Text(message)
          .font(.subheadline)
          .foregroundStyle(.secondary)
          .lineLimit(2)
          .fixedSize(horizontal: false, vertical: true)
      }

      Spacer(minLength: 12)

      ViewThatFits(in: .horizontal) {
        HStack(spacing: 8) {
          actionButtons
        }
        VStack(alignment: .trailing, spacing: 8) {
          actionButtons
        }
      }

      Button(action: onDismiss) {
        Image(systemName: "xmark")
          .font(.subheadline)
          .foregroundStyle(.secondary)
      }
      .buttonStyle(.plain)
      .help(L10n.key("trial_expired_dismiss"))
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

  @ViewBuilder
  private var actionButtons: some View {
    Button(L10n.key("purchase_section_restore"), action: onRestore)
      .buttonStyle(.bordered)
      .layoutPriority(1)

    Button(L10n.key("purchase_section_purchase"), action: onPurchase)
      .buttonStyle(.borderedProminent)
      .layoutPriority(1)
  }
}
