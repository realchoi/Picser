//
//  TagRecommendationTelemetry.swift
//
//  Created by Eric Cai on 2025/11/11.
//

import Foundation

struct TagRecommendationContext: Hashable, Sendable {
  let imagePath: String
  let directory: String
  let scopeSignature: Int
}

struct TagRecommendationCounters: Sendable {
  var served: Int = 0
  var selected: Int = 0
}

actor TagRecommendationTelemetry {
  static let shared = TagRecommendationTelemetry()

  private var counters: [Int64: TagRecommendationCounters] = [:]
  private var contextServedCount: [TagRecommendationContext: Int] = [:]
  private var contextSelectionCount: [TagRecommendationContext: Int] = [:]

  func recordServed(tagIDs: [Int64], context: TagRecommendationContext) {
    guard !tagIDs.isEmpty else { return }
    contextServedCount[context, default: 0] += tagIDs.count
    for id in tagIDs {
      var counter = counters[id] ?? TagRecommendationCounters()
      counter.served += 1
      counters[id] = counter
    }
  }

  func recordSelection(tagID: Int64, context: TagRecommendationContext) {
    contextSelectionCount[context, default: 0] += 1
    var counter = counters[tagID] ?? TagRecommendationCounters()
    counter.selected += 1
    counters[tagID] = counter
  }

  func snapshot() -> [Int64: TagRecommendationCounters] {
    counters
  }

  func contextSnapshot() -> (served: [TagRecommendationContext: Int], selected: [TagRecommendationContext: Int]) {
    (contextServedCount, contextSelectionCount)
  }
}
