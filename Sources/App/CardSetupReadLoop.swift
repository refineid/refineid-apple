// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// Keeps a setup operation alive while a fresh NFC field can recover the read.
@MainActor
internal enum CardSetupReadLoop {
  /// Lets the system release the previous field before another request.
  internal static let retryInterval: Duration = .seconds(1)

  /// Each attempt requests field teardown before another can start.
  ///
  /// A cancellation stops the operation without spending another card attempt.
  internal static func run<Outcome>(
    attempt: () async -> Outcome,
    shouldRetry: (Outcome) -> Bool,
    pause: () async throws -> Void
  ) async -> Outcome? {
    while !Task.isCancelled {
      let outcome = await attempt()
      guard shouldRetry(outcome) else { return outcome }
      do {
        try await pause()
      } catch {
        return nil
      }
    }
    return nil
  }
}
