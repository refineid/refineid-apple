// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation
import Testing

/// The identity row reads the reader through an observed object, so the
/// line moves when a reader is attached or removed.
@Suite
internal struct IdentityStateViewObservationTests {
  private static var source: String {
    get throws {
      let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
      return try String(
        contentsOf: root.appending(path: "Sources/App/IdentityStateView.swift"),
        encoding: .utf8
      )
    }
  }

  /// The row observes the reader instead of reading the singleton.
  @Test
  internal func readerStateIsObserved() throws {
    let text = try Self.source
    #expect(text.contains("@ObservedObject private var cardPresence = CardPresence.shared"))
    #expect(!text.contains("CardPresence.shared.is"))
  }
}
