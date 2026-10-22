// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// The storage exchange of a pairing ceremony (RAPP v26.10.21 §4.3 item 4):
/// each endpoint confirms that its record is durably stored, and the
/// pairing is active only once both confirmations have been exchanged.
///
/// The authenticated pairing channel stays open for the two
/// `pairing.stored` messages; ``intoActive()`` is the only way to obtain
/// an ``ActivePairing``, and it exists only with both confirmations.
internal struct PairingStorage {
  internal let pairIdentifier: Data

  private var channel: RappMessageChannel

  private var localStoredSent = false

  private var peerStored = false

  /// Whether both the local confirmation was sent and the peer's received.
  internal var isConfirmed: Bool { localStoredSent && peerStored }

  internal init(pairIdentifier: Data, channel: RappMessageChannel) {
    self.pairIdentifier = pairIdentifier
    self.channel = channel
  }

  /// Confirms to the peer that the local record is durably stored; sent
  /// once, after storage reported the write.
  internal mutating func sendStored() throws -> Data {
    guard !localStoredSent else { throw PairingError.duplicateMessage }
    let frame: Data
    do {
      frame = try channel.seal(
        .pairingStored, body: PairingStored(pairIdentifier: pairIdentifier).body())
    } catch {
      throw PairingError.noise
    }
    localStoredSent = true
    return frame
  }

  /// Accepts the peer's storage confirmation; one naming another pairing
  /// is an authenticated protocol violation.
  internal mutating func receiveStored(_ frame: Data) throws {
    guard !peerStored else { throw PairingError.duplicateMessage }
    let envelope: Envelope
    do {
      envelope = try channel.open(frame)
    } catch let failure as RappOpenFailure {
      throw PairingError.open(failure)
    } catch {
      throw PairingError.open(.authenticatedProtocolViolation)
    }
    guard envelope.messageType == .pairingStored else { throw PairingError.unexpectedMessage }
    let stored: PairingStored
    do {
      stored = try PairingStored.from(body: envelope.body)
    } catch let error as MessageFieldError {
      throw PairingError.message(error)
    }
    guard stored.pairIdentifier == pairIdentifier else {
      throw PairingError.pairIdentifierMismatch
    }
    peerStored = true
  }

  /// Closes the pairing channel and proves the pairing active.
  ///
  /// Consuming: the channel is spent with the proof, so no further message
  /// can travel on it.
  internal consuming func intoActive() throws -> ActivePairing {
    guard isConfirmed else { throw PairingError.storageUnconfirmed }
    return ActivePairing(pairIdentifier: pairIdentifier)
  }
}
