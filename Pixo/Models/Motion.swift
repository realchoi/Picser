//
//  Motion.swift
//  Pixo
//
//  Centralized animation timings and curves for consistent UX.
//

import SwiftUI

enum Motion {
  enum Duration {
    static let ultraFast: Double = 0.08   // micro interactions (pinch change)
    static let fast: Double = 0.10        // wheel zoom tick, quick fades
    static let medium: Double = 0.12      // lightweight overlays
    static let standard: Double = 0.15    // common UI transitions
    static let minimap: Double = 0.18     // subtle orientation change
    static let panEnd: Double = 0.20      // pan settle
    static let slow: Double = 0.25        // fit-to-view animations
    static let reset: Double = 0.30       // reset/large state change
  }

  enum Anim {
    static let ultraFast: Animation = .easeInOut(duration: Duration.ultraFast)
    static let fast: Animation = .easeInOut(duration: Duration.fast)
    static let medium: Animation = .easeInOut(duration: Duration.medium)
    static let standard: Animation = .easeInOut(duration: Duration.standard)
    static let minimap: Animation = .easeInOut(duration: Duration.minimap)
    static let panEnd: Animation = .easeInOut(duration: Duration.panEnd)
    static let slow: Animation = .easeInOut(duration: Duration.slow)
    static let reset: Animation = .easeInOut(duration: Duration.reset)
  }
}

