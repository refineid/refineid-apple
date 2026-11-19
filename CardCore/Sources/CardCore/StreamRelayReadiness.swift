// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// Answers callers waiting for a stream listener's readiness, once.
///
/// The first readiness signal wins; later signals change nothing
/// already answered.
internal final class StreamRelayReadiness: @unchecked Sendable {
  private let lock = NSLock()
  private var waiters: [CheckedContinuation<UInt16, Error>] = []
  private var result: Result<UInt16, Error>?

  /// Suspends until readiness is noted or the wait fails, once.
  internal func wait() async throws -> UInt16 {
    try await withCheckedThrowingContinuation { continuation in
      lock.withLock {
        if let result {
          continuation.resume(with: result)
        } else {
          waiters.append(continuation)
        }
      }
    }
  }

  /// Records the platform reporting ready with the port bound then, if any.
  internal func noteReady(port: UInt16?) {
    if let bound = port, bound != 0 {
      settle(.success(bound))
    } else {
      settle(.failure(StreamRelayTransportError.unreachable))
    }
  }

  /// Records the platform reporting failure.
  internal func noteFailed() {
    settle(.failure(StreamRelayTransportError.unreachable))
  }

  /// Answers every waiter with the channel ending, unless already answered.
  internal func fail(_ error: StreamRelayTransportError) {
    settle(.failure(error))
  }

  private func settle(_ settled: Result<UInt16, Error>) {
    let pending: [CheckedContinuation<UInt16, Error>] = lock.withLock {
      guard result == nil else { return [] }
      result = settled
      let waiting = waiters
      waiters.removeAll()
      return waiting
    }
    for waiter in pending {
      waiter.resume(with: settled)
    }
  }
}
