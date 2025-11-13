//
//  SubscriptionGraceBanner.swift
//
//  Created by Eric Cai on 2025/11/1.
//

import SwiftUI
import Combine

/// 订阅已过期但仍处于宽限期时的提示横幅
struct SubscriptionGraceBanner: View {
  let status: SubscriptionStatus
  let onPurchase: () -> Void
  let onRestore: () -> Void
  let onDismiss: () -> Void

  @State private var now: Date = Date()
  private let timer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

  private var graceEndDate: Date? {
    status.expirationDate?.addingTimeInterval(3 * 24 * 60 * 60)
  }

  private var message: String {
    guard let expiration = status.expirationDate, let graceEnd = graceEndDate else {
      return L10n.string("subscription_grace_message_generic")
    }

    let expirationString = FormatUtils.dateString(from: expiration)
    let remaining = SubscriptionGraceBanner.normalizeRemainingDescription(
      TrialFormatter.remainingDescription(now: now, endDate: graceEnd)
    )
    let template = L10n.string("subscription_grace_message_with_remaining")
    return String(format: template, expirationString, remaining)
  }

  var body: some View {
    HStack(alignment: .top, spacing: 16) {
      Image(systemName: "clock.badge.exclamationmark")
        .font(.title2)
        .foregroundStyle(.orange)

      VStack(alignment: .leading, spacing: 6) {
        Text(L10n.string("subscription_grace_title"))
          .font(.headline)
        Text(message)
          .font(.subheadline)
          .foregroundStyle(.secondary)
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
    .onReceive(timer) { value in
      now = value
    }
    .onAppear {
      now = Date()
    }
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

  static func normalizeRemainingDescription(_ text: String) -> String {
    var value = text.trimmingCharacters(in: .whitespacesAndNewlines)

    if value.hasSuffix(" remaining") {
      value = String(value.dropLast(" remaining".count)).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    if value.hasPrefix("Less than a minute") {
      return value
    }

    if value.hasPrefix("剩余时间不足") {
      value = value.replacingOccurrences(of: "剩余时间", with: "").trimmingCharacters(in: .whitespaces)
    } else if value.hasPrefix("剩余") {
      value = String(value.dropFirst(2)).trimmingCharacters(in: .whitespaces)
    }

    return value.isEmpty ? text : value
  }
}
