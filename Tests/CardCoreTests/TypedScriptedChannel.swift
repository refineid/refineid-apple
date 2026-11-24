// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation
import Testing

@testable import CardCore

/// A typed scripted `CardChannel` matching exact APDU command/response pairs
/// assembled from domain types and named constants (no hand-typed hex).
internal final class TypedScriptedChannel: CardChannel {
  internal struct UnexpectedRequest: Error {}

  private var script: [(request: Data, response: Data)]

  internal var readChunkLength: ReadChunkLength { .plain }

  internal var isExhausted: Bool { script.isEmpty }

  internal init(_ script: [(Data, Data)]) {
    self.script = script.map { pair in (request: pair.0, response: pair.1) }
  }

  internal func transmit(_ payload: Data) throws -> Data {
    guard let next = script.first, next.request == payload else {
      Issue.record("unexpected transmit: \(payload.count) bytes")
      throw UnexpectedRequest()
    }
    script.removeFirst()
    return next.response
  }
}
