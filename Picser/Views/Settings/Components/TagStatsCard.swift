//
//  TagStatsCard.swift
//
//  Created by Eric Cai on 2025/11/11.
//

import SwiftUI

struct TagStatsCard: View {
  let total: Int
  let used: Int
  let unused: Int

  var body: some View {
    GroupBox {
      VStack(alignment: .leading, spacing: 12) {
        Text(L10n.string("tag_settings_stats_title"))
          .font(.headline)
        HStack {
          statColumn(title: L10n.string("tag_settings_stats_total"), value: total)
          statColumn(title: L10n.string("tag_settings_stats_used"), value: used)
          statColumn(title: L10n.string("tag_settings_stats_unused"), value: unused)
        }
      }
      .padding(12)
    }
  }

  private func statColumn(title: String, value: Int) -> some View {
    VStack {
      Text("\(value)")
        .font(.title3.bold())
      Text(title)
        .font(.caption)
        .foregroundColor(.secondary)
    }
    .frame(maxWidth: .infinity)
  }
}
