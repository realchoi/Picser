//
//  KeyRecorderView.swift
//  PicTube
//
//  Created by Eric Cai on 2025/8/19.
//

import AppKit
import SwiftUI

// 快捷键录制视图
struct KeyRecorderView: View {
  @Binding var selectedKey: ModifierKey
  @State private var isRecording: Bool = false
  @State private var displayText: String = ""

  var body: some View {
    HStack {
      // 显示当前选中的快捷键
      Text(displayText)
        .frame(minWidth: 120, alignment: .leading)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(4)
        .overlay(
          RoundedRectangle(cornerRadius: 4)
            .stroke(isRecording ? Color.accentColor : Color.gray.opacity(0.3), lineWidth: 1)
        )

      // 录制按钮
      Button(isRecording ? "停止录制" : "录制") {
        if isRecording {
          stopRecording()
        } else {
          startRecording()
        }
      }
      .buttonStyle(.bordered)

      // 清除按钮
      Button("清除") {
        selectedKey = .none
        updateDisplayText()
      }
      .buttonStyle(.bordered)
    }
    .onAppear {
      updateDisplayText()
    }
    .onChange(of: selectedKey) { _ in
      updateDisplayText()
    }
  }

  private func updateDisplayText() {
    displayText = selectedKey.displayName
  }

  private func startRecording() {
    isRecording = true
    displayText = "按下修饰键..."

    // 创建键盘录制窗口
    let recorder = KeyRecorderWindow { modifierKey in
      DispatchQueue.main.async {
        self.selectedKey = modifierKey
        self.stopRecording()
      }
    }
    recorder.startRecording()
  }

  private func stopRecording() {
    isRecording = false
    updateDisplayText()
  }
}

// 快捷键录制窗口
class KeyRecorderWindow: NSWindow {
  private let completion: (ModifierKey) -> Void
  private var eventMonitor: Any?

  init(completion: @escaping (ModifierKey) -> Void) {
    self.completion = completion

    super.init(
      contentRect: NSRect(x: 0, y: 0, width: 1, height: 1),
      styleMask: [],
      backing: .buffered,
      defer: false
    )

    self.isOpaque = false
    self.backgroundColor = NSColor.clear
    self.ignoresMouseEvents = true
    self.level = .floating
  }

  func startRecording() {
    // 监听全局按键事件
    eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown, .flagsChanged]) {
      [weak self] event in
      self?.handleKeyEvent(event)
    }

    // 也监听本地事件
    NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
      self?.handleKeyEvent(event)
      return event
    }

    // 显示窗口（虽然不可见）
    self.makeKeyAndOrderFront(nil)
  }

  private func handleKeyEvent(_ event: NSEvent) {
    let modifierFlags = event.modifierFlags

    // 检查修饰键
    var detectedKey: ModifierKey = .none

    if modifierFlags.contains(.command) {
      detectedKey = .command
    } else if modifierFlags.contains(.option) {
      detectedKey = .option
    } else if modifierFlags.contains(.control) {
      detectedKey = .control
    } else if modifierFlags.contains(.shift) {
      detectedKey = .shift
    }

    // 如果检测到有效的修饰键，完成录制
    if detectedKey != .none {
      stopRecording()
      completion(detectedKey)
    }
  }

  private func stopRecording() {
    if let monitor = eventMonitor {
      NSEvent.removeMonitor(monitor)
      eventMonitor = nil
    }
    self.close()
  }

  deinit {
    stopRecording()
  }
}

// 预览
#Preview {
  VStack {
    Text("缩放快捷键:")
    KeyRecorderView(selectedKey: .constant(.control))

    Text("拖拽快捷键:")
    KeyRecorderView(selectedKey: .constant(.none))
  }
  .padding()
}
