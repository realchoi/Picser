//
//  ImageTransform.swift
//  PicTube
//
//  Lightweight model to represent per-image view transforms.
//

import Foundation

enum ImageRotation: Int, CaseIterable, Equatable {
  case deg0 = 0
  case deg90 = 90
  case deg180 = 180
  case deg270 = 270

  func rotated(by delta: Int) -> ImageRotation {
    let values = [0, 90, 180, 270]
    let current = self.rawValue
    // Normalize to one of the four right-angle rotations
    let next = ((current + delta) % 360 + 360) % 360
    let snapped = values.min(by: { abs($0 - next) < abs($1 - next) }) ?? 0
    switch snapped {
    case 90: return .deg90
    case 180: return .deg180
    case 270: return .deg270
    default: return .deg0
    }
  }

  var degrees: Double { Double(rawValue) }
  var isRightAngle: Bool { self != .deg0 }
}

struct ImageTransform: Equatable {
  var rotation: ImageRotation = .deg0
  var mirrorH: Bool = false
  var mirrorV: Bool = false

  static let identity = ImageTransform()
}

