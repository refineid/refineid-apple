// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation
import Testing

@testable import RappEngine

/// A record that could not be stored is answered with `pairing.abort`, in
/// place of `pairing.stored` (RAPP v26.11.8 §4.3 item 4).
@Suite("Pairing storage abort")
internal struct PairingStorageAbortTests {
  private static let pairIdentifier = Data(repeating: 1, count: PairRecordSize.pairIdentifier)

  @Test("The abort is an authenticated pairing.abort with its reason")
  internal func abortFrame() throws {
    let channels = matchedMessageChannels()
    var receiver = channels.receiver
    var storage = PairingStorage(pairIdentifier: Self.pairIdentifier, channel: channels.sender)

    let envelope = try receiver.open(try storage.sendAbort())

    #expect(envelope.messageType == .pairingAbort)
    #expect(envelope.body == ["reason": .text(PairingStorage.notStoredReason)])
    #expect(!storage.isConfirmed)
  }

  @Test("No abort follows a storage confirmation")
  internal func noAbortAfterStored() throws {
    var storage = PairingStorage(
      pairIdentifier: Self.pairIdentifier, channel: matchedMessageChannels().sender)
    _ = try storage.sendStored()
    #expect(throws: PairingError.duplicateMessage) { try storage.sendAbort() }
  }
}
