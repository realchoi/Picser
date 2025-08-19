//
//  KeyRecorderView.swift
//  PicTube
//
//  Created by Eric Cai on 2025/8/19.
//

import AppKit
import SwiftUI

// 修饰键选择器视图
struct KeyRecorderView: View {
  @Binding var selectedKey: ModifierKey

  var body: some View {
    HStack {
      // 修饰键选择器
      Picker("", selection: $selectedKey) {
        ForEach(ModifierKey.availableKeys()) { key in
          Text(key.displayName)
            .tag(key)
        }
      }
      .pickerStyle(.menu)
      .frame(minWidth: 120)
    }
  }
}

// 预览
#Preview {
  VStack {
    Text("缩放快捷键:")
    KeyRecorderView(selectedKey: .constant(.control))

    Text("拖拽快捷键:")
    KeyRecorderView(selectedKey: .constant(.command))
  }
  .padding()
}
