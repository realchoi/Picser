//
//  TagEmptyStateView.swift
//
//  Created by Eric Cai on 2025/11/11.
//

import SwiftUI

struct TagEmptyStateView: View {
  let systemImage: String
  let message: String
  var minHeight: CGFloat? = nil

  var body: some View {
    VStack(spacing: 8) {
      Image(systemName: systemImage)
        .font(.system(size: 32))
        .foregroundColor(.secondary)
      Text(message)
        .font(.callout)
        .foregroundColor(.secondary)
    }
    .frame(maxWidth: .infinity, minHeight: minHeight)
  }
}
