//
//  AsyncSemaphore.swift
//  PicTube
//
//  Created by Eric Cai on 2025/8/21.
//

import Foundation

actor AsyncSemaphore {
  private let limit: Int
  private var permits: Int
  private var waiters: [CheckedContinuation<Void, Never>] = []

  init(limit: Int) {
    self.limit = max(1, limit)
    self.permits = max(1, limit)
  }

  func acquire() async {
    if permits > 0 {
      permits -= 1
      return
    }
    await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
      waiters.append(continuation)
    }
  }

  func release() {
    if !waiters.isEmpty {
      let cont = waiters.removeFirst()
      cont.resume()
    } else {
      permits = min(permits + 1, limit)
    }
  }
}
