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
    let normalized = urls.map { $0.standardizedFileURL }

    // 同步处理外部打开
    let batch = await FileOpenService.loadImageBatch(
      from: normalized,
      recordRecents: recordRecents,
      securityScopedInputs: urls
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
