//
//  TagFeedbackBanner.swift
//
//  Created by Eric Cai on 2025/11/10.
//

import SwiftUI

/// 标签设置中展示操作结果的提示横幅
struct TagFeedbackBanner: View {
  let feedback: TagOperationFeedback
  let onDismiss: () -> Void

  private var iconName: String {
    feedback.isSuccess ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
  }

  private var accentColor: Color {
    feedback.isSuccess ? .green : .orange
  }

  private var timestampText: String {
    LocalizedDateFormatter.shortTimestamp(for: feedback.timestamp)
  }

  var body: some View {
    HStack(alignment: .center, spacing: 12) {
      Image(systemName: iconName)
        .font(.title3)
        .foregroundStyle(accentColor)

      VStack(alignment: .leading, spacing: 2) {
        Text(feedback.message)
          .font(.subheadline)
        Text(timestampText)
          .font(.caption2)
          .foregroundStyle(.secondary)
      }

      Spacer(minLength: 8)

      Button(action: onDismiss) {
        Image(systemName: "xmark.circle.fill")
          .symbolRenderingMode(.palette)
          .foregroundStyle(
            Color.primary.opacity(0.3),
            Color.primary.opacity(0.08)
          )
      }
      .buttonStyle(.plain)
      .help(L10n.key("tag_feedback_dismiss_button"))
      .accessibilityLabel(Text(l10n: "tag_feedback_dismiss_button"))
    }
    .padding(.vertical, 10)
    .padding(.horizontal, 14)
    .background(
      RoundedRectangle(cornerRadius: 14, style: .continuous)
        .fill(accentColor.opacity(0.12))
    )
    .overlay(
      RoundedRectangle(cornerRadius: 14, style: .continuous)
        .stroke(accentColor.opacity(0.35), lineWidth: 1)
    )
  }
}
