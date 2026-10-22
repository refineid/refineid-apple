// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// Independent per-direction sequence enforcement for one session.
///
/// Each direction advances by exactly one. A repeat, a gap, a rollback, or an
/// envelope naming another session is refused and leaves the guard unchanged,
/// so a rejected message can never advance the window.
internal struct SequenceGuard {
  private let sessionIdentifier: Data
  private var nextSend: UInt64 = 0
  private var nextReceive: UInt64 = 0

  internal var expectedNextReceive: UInt64 { nextReceive }

  internal init(sessionIdentifier: Data) {
    self.sessionIdentifier = sessionIdentifier
  }

  /// Allocate the only legal sequence for the next outgoing message.
  internal mutating func nextOutgoing() throws -> UInt64 {
    let sequence = nextSend
    guard nextSend < UInt64.max else { throw WireError.sequenceWrapped }
    nextSend += 1
    return sequence
  }

  /// Accept an incoming envelope only at its exact expected position.
  ///
  /// The cipher state beneath this one already advances a nonce per frame
  /// in each direction, so a replayed, reordered or skipped frame fails to
  /// decrypt and never reaches here. What this refuses is a decrypted
  /// envelope whose named session or sequence contradicts its own nonce
  /// position - a peer sealing nonconforming envelopes.
  internal mutating func acceptIncoming(sessionIdentifier: Data, sequence: UInt64) throws {
    guard sessionIdentifier == self.sessionIdentifier else { throw WireError.wrongSession }
    guard sequence == nextReceive else {
      throw WireError.wrongSequence(expected: nextReceive, got: sequence)
    }
    guard nextReceive < UInt64.max else { throw WireError.sequenceWrapped }
    nextReceive += 1
  }
}
