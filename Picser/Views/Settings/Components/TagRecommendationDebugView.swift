//
//  TagRecommendationDebugView.swift
//
//  Created by Eric Cai on 2025/11/11.
//

import SwiftUI

struct TagRecommendationDebugView: View {
  let allTags: [TagRecord]
  let dismiss: () -> Void

  @State private var rows: [Row] = []

  struct Row: Identifiable {
    let id: Int64
    let name: String
    let served: Int
    let selected: Int
    var conversion: Double {
      guard served > 0 else { return 0 }
      return Double(selected) / Double(served)
    }
  }

  var body: some View {
    NavigationStack {
      List(rows) { row in
        HStack {
          VStack(alignment: .leading, spacing: 2) {
            Text(row.name)
              .font(.headline)
            Text("展示 \(row.served) · 选中 \(row.selected)")
              .font(.caption)
              .foregroundColor(.secondary)
          }
          Spacer()
          Text(row.conversion, format: .percent.precision(.fractionLength(1)))
            .font(.subheadline.monospacedDigit())
        }
        .padding(.vertical, 4)
      }
      .navigationTitle("推荐统计")
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("关闭", action: dismiss)
        }
        ToolbarItem(placement: .primaryAction) {
          Button("刷新", action: refresh)
        }
      }
      .task { refresh() }
    }
  }

  private func refresh() {
    Task {
      let counters = await TagRecommendationTelemetry.shared.snapshot()
      let lookup = Dictionary(uniqueKeysWithValues: allTags.map { ($0.id, $0.name) })
      let mapped = counters.map { id, counter in
        Row(
          id: id,
          name: lookup[id] ?? "#\(id)",
          served: counter.served,
          selected: counter.selected
        )
      }
      let sorted = mapped.sorted { lhs, rhs in
        if lhs.conversion == rhs.conversion {
          return lhs.served > rhs.served
        }
        return lhs.conversion > rhs.conversion
      }
      await MainActor.run {
        rows = sorted
      }
    }
  }
}
