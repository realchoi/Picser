//
//  ExternalOpenCoordinator.swift
//
//  Created by Eric Cai on 2025/10/09.
//

import AppKit
import Combine
import Foundation

@MainActor
final class ExternalOpenCoordinator: ObservableObject {
  @Published private(set) var latestBatch: ImageBatch?

  var latestBatchPublisher: AnyPublisher<ImageBatch, Never> {
    $latestBatch
      .compactMap { $0 }
      .eraseToAnyPublisher()
  }

  func handleIncoming(urls: [URL], recordRecents: Bool = true) async {
    guard !urls.isEmpty else { return }

    // 应用单图片目录扩展逻辑
    let (inputs, scopedInputs, initialImage) = await FileOpenService.applySingleImageDirectoryExpansion(
      urls: urls,
      context: "External"
    )

    // 同步处理外部打开
    let batch = await FileOpenService.loadImageBatch(
      from: inputs,
      recordRecents: recordRecents,
      securityScopedInputs: scopedInputs,
      initiallySelectedImage: initialImage
    )

    // 设置latestBatch，等待ContentView消费
    latestBatch = batch
  }

  func consumeLatestBatch() -> ImageBatch? {
    defer { latestBatch = nil }
    return latestBatch
  }

  func clearLatestBatch() {
    latestBatch = nil
  }
}
