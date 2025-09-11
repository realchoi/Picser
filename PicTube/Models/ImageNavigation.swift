//
//  ImageNavigation.swift
//  PicTube
//
//  Small utility to compute next image index from a key press.
//

import Foundation
import SwiftUI

enum ImageNavigation {
  /// Compute next index for navigation keys based on user preference.
  /// Returns nil when the key does not trigger navigation under current mode
  /// or when totalCount <= 0.
  static func nextIndex(
    for key: KeyEquivalent,
    mode: ImageNavigationKey,
    currentIndex: Int,
    totalCount: Int
  ) -> Int? {
    guard totalCount > 0, currentIndex >= 0 else { return nil }

    let prev = (currentIndex - 1 + totalCount) % totalCount
    let next = (currentIndex + 1) % totalCount

    switch mode {
    case .leftRight:
      if key == .leftArrow { return prev }
      if key == .rightArrow { return next }
    case .upDown:
      if key == .upArrow { return prev }
      if key == .downArrow { return next }
    case .pageUpDown:
      if key == .pageUp { return prev }
      if key == .pageDown { return next }
    }
    return nil
  }
}
