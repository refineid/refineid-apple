// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// Per-document timestamp spacing hooks for signing flows.
extension TimestampClient {
  /// The throttle governing timestamp requests in the current task.
  private static var effectiveThrottle: TimestampThrottle {
    #if DEBUG
      if let throttle {
        return throttle
      }
    #endif
    return TimestampThrottle.shared
  }

  /// Scopes follow-up timestamp exchanges (such as an archive timestamp after
  /// a signature timestamp) to a single document or container, while spacing
  /// separate documents by ``TimestampThrottle/minimumDocumentSpacing``.
  internal static func forOneDocument<Value>(
    _ operation: () async throws -> Value
  ) async rethrows -> Value {
    let session = Self.effectiveThrottle.makeDocumentSession()
    return try await Self.$documentSession.withValue(session) {
      try await operation()
    }
  }

  /// Returns the current document's session, or a fresh single-document session.
  internal static func activeDocumentSession() -> TimestampThrottle.DocumentSession {
    Self.documentSession ?? Self.effectiveThrottle.makeDocumentSession()
  }
}
