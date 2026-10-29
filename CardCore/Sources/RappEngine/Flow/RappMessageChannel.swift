// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// The encrypted channel with envelope framing and sequence enforcement.
///
/// Sealing allocates the one legal outgoing sequence; opening refuses anything
/// that is not the exact next incoming one, so a replayed or reordered frame
/// cannot advance the window.
internal struct RappMessageChannel {
  private var channel: RappSecureChannel

  private var sequence: SequenceGuard

  private let sessionIdentifier: Data

  internal init(channel: RappSecureChannel, sessionIdentifier: Data) {
    self.channel = channel
    self.sessionIdentifier = sessionIdentifier
    self.sequence = SequenceGuard(sessionIdentifier: sessionIdentifier)
  }

  internal mutating func seal(
    _ messageType: MessageType, body: [String: WireValue]
  ) throws -> Data {
    let envelope = Envelope(
      messageType: messageType,
      sessionIdentifier: sessionIdentifier,
      sequence: try sequence.nextOutgoing(),
      body: body)
    return try channel.seal(try envelope.encoded())
  }

  /// Decrypt one frame into a schema-checked, correctly sequenced envelope.
  ///
  /// The cipher's counter nonce already refuses a replayed, reordered or
  /// skipped frame, so a decrypted envelope naming another session or a
  /// sequence off its nonce position can only be a peer that seals
  /// nonconforming envelopes - an authenticated protocol violation that
  /// closes the session (RAPP v26.10.29 §7.2).
  internal mutating func open(_ frame: Data) throws -> Envelope {
    var decoded: Envelope?
    var guardCopy = sequence
    _ = try channel.open(frame) { plaintext in
      let envelope = try Envelope.decode(plaintext)
      try guardCopy.acceptIncoming(
        sessionIdentifier: envelope.sessionIdentifier, sequence: envelope.sequence)
      decoded = envelope
    }
    guard let envelope = decoded else { throw RappOpenFailure.authenticatedProtocolViolation }
    sequence = guardCopy
    return envelope
  }
}
