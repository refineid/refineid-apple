// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation
import Testing

@testable import RefineIDTestHost

/// Bodies on the chain run in order, and a body calling back in proceeds.
@Suite
internal struct SerialChainTests {
  /// A log the bodies append to, read back in order.
  private final class Log: @unchecked Sendable {
    private let lock = NSLock()
    private var lines: [String] = []

    func append(_ line: String) {
      lock.lock()
      lines.append(line)
      lock.unlock()
    }

    func read() -> [String] {
      lock.lock()
      defer { lock.unlock() }
      return lines
    }
  }

  private static let firstHoldMs = 50

  @Test("Two bodies run one after the other in arrival order")
  internal func bodiesRunInOrder() async {
    let chain = SerialChain()
    let log = Log()
    async let first: Void = chain.run {
      log.append("first-start")
      try? await Task.sleep(for: .milliseconds(Self.firstHoldMs))
      log.append("first-end")
    }
    try? await Task.sleep(for: .milliseconds(1))
    async let second: Void = chain.run {
      log.append("second")
    }
    _ = await (first, second)
    #expect(log.read() == ["first-start", "first-end", "second"])
  }

  @Test("A body that calls back into the chain completes instead of waiting for itself")
  internal func reentrantCallProceeds() async {
    let chain = SerialChain()
    let log = Log()
    let answer: Int = await chain.run {
      log.append("outer")
      let inner: Int = await chain.run {
        log.append("inner")
        return 1
      }
      return inner + 1
    }
    #expect(answer == 2)
    #expect(log.read() == ["outer", "inner"])
  }
}
