// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation
import Synchronization
import Testing

@testable import RappEngine

/// The engine names each message it refuses to the receiver installed.
@Suite("RAPP refusal log")
internal struct RefusalLogTests {
  /// Every line the engine named while this suite ran; other suites may
  /// add theirs.
  private static let lines = Mutex<[String]>([])

  @Test("A card status without the reader's attachment is named with the rule it broke")
  internal func cardStatusRefusalIsNamed() throws {
    RappRefusalLog.install { line in Self.lines.withLock { $0.append(line) } }
    let session = try establishedSession(
      try PairedBridges.pair(granting: everyProfile),
      nowMilliseconds: OperationFixture.startMilliseconds)
    var body = RappCardStatus(card: .absent, reader: .attached).wireBody
    body["reader_attached"] = nil
    _ = session.requester.receiveFrame(
      bytes: try injected(.cardStatus, body, from: session.custodian),
      nowMs: OperationFixture.startMilliseconds)
    let expected = "card.status: \(WireError.missingField(field: "reader_attached"))"
    #expect(Self.lines.withLock { $0.contains(expected) })
  }
}
