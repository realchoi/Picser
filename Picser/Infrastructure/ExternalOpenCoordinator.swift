//
//  ExternalOpenCoordinator.swift
//
//  Created by Eric Cai on 2025/10/09.
//

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

  func handleIncoming(urls: [URL], recordRecents: Bool = true) {
    guard !urls.isEmpty else { return }
    let normalized = urls.map { $0.standardizedFileURL }
    Task(priority: .userInitiated) { [weak self, normalized] in
      guard let self else { return }
      let batch = await FileOpenService.loadImageBatch(from: normalized, recordRecents: recordRecents)
      self.latestBatch = batch
    }
  }

  func consumeLatestBatch() -> ImageBatch? {
    defer { latestBatch = nil }
    return latestBatch
  }

  func clearLatestBatch() {
    latestBatch = nil
  }
}
