//
//  TagInspectionCard.swift
//
//  Created by Eric Cai on 2025/11/11.
//

import SwiftUI

struct TagInspectionCard: View {
  let summary: TagInspectionSummary
  let isInspecting: Bool
  let descriptionText: String
  let onInspect: () -> Void

  var body: some View {
    GroupBox {
      VStack(alignment: .leading, spacing: 12) {
        header
        if !summary.missingPaths.isEmpty && !isInspecting {
          Divider()
          missingPathsView
        }
      }
      .padding(12)
    }
  }

  private var header: some View {
    HStack(alignment: .firstTextBaseline, spacing: 16) {
      VStack(alignment: .leading, spacing: 4) {
        Text(L10n.string("tag_settings_inspection_title"))
          .font(.headline)
        Text(descriptionText)
          .font(.caption)
          .foregroundColor(.secondary)
      }
      Spacer()
      Button(action: onInspect) {
        Label {
          Text(
            L10n.string(
              isInspecting
                ? "tag_settings_inspection_running"
                : "tag_settings_inspection_button"
            )
          )
        } icon: {
          ZStack {
            Image(systemName: "stethoscope")
              .opacity(isInspecting ? 0 : 1)
            ProgressView()
              .progressViewStyle(.circular)
              .controlSize(.small)
              .opacity(isInspecting ? 1 : 0)
          }
          .frame(width: 18, height: 18)
        }
        .labelStyle(.titleAndIcon)
      }
      .buttonStyle(.borderedProminent)
      .disabled(isInspecting)
    }
  }

  private var missingPathsView: some View {
    let preview = Array(summary.missingPaths.prefix(5))
    return VStack(alignment: .leading, spacing: 6) {
      Text(
        String(
          format: L10n.string("tag_settings_inspection_missing_title"),
          summary.missingPaths.count
        )
      )
      .font(.caption)
      .foregroundColor(.secondary)

      ForEach(preview, id: \.self) { path in
        Label(path, systemImage: "exclamationmark.triangle")
          .font(.caption2)
          .lineLimit(1)
          .foregroundColor(.secondary)
      }

      if summary.missingPaths.count > preview.count {
        Text(
          String(
            format: L10n.string("tag_settings_inspection_missing_more"),
            summary.missingPaths.count - preview.count
          )
        )
        .font(.caption2)
        .foregroundColor(.secondary)
      }
    }
  }
}
