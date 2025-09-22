//
//  WindowCommandHandlers.swift
//  Pixor
//
//  Created by Eric Cai on 2025/09/22.
//

import Foundation
import SwiftUI

struct WindowCommandHandlers {
  let openFileOrFolder: () -> Void
  let refresh: () -> Void
  let rotateCCW: () -> Void
  let rotateCW: () -> Void
  let mirrorHorizontal: () -> Void
  let mirrorVertical: () -> Void
  let resetTransform: () -> Void
  let openResolvedURL: (URL) -> Void
}

struct WindowCommandHandlersKey: FocusedValueKey {
  typealias Value = WindowCommandHandlers
}

extension FocusedValues {
  var windowCommandHandlers: WindowCommandHandlers? {
    get { self[WindowCommandHandlersKey.self] }
    set { self[WindowCommandHandlersKey.self] = newValue }
  }
}
