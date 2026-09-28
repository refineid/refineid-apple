// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// The pairing ceremony, from a published or scanned offer to a stored
/// pairing.
///
/// One bridge runs one ceremony. It holds the offer's one-use secret, so a
/// cancelled or completed bridge is spent and refuses further calls.
public final class RappPairingBridge: @unchecked Sendable {
  /// Where the ceremony has reached.
  internal enum Phase {
    case offer
    case cpace(cpace: RappCpaceState, offer: PairingOffer, candidateId: String)
    case handshaking(PairingHandshake)
    case confirming(PairingConfirmation)
    case finished
    case cancelled
  }

  internal let lock = NSLock()
  internal let role: EndpointRole
  internal let offer: PairingOffer
  internal let deadline: PairingOfferDeadline
  internal let localKeys: PairKeyMaterial
  internal var phase = Phase.offer

  internal init(
    role: EndpointRole,
    offer: PairingOffer,
    startedAtMonotonicMs: UInt64
  ) throws {
    self.role = role
    self.offer = offer
    do {
      self.deadline = try PairingOfferDeadline(
        offer: offer, startedAtMilliseconds: startedAtMonotonicMs)
    } catch {
      throw RappBindingError.InvalidInput
    }
    self.localKeys = PairKeyMaterial()
  }

  internal func locked<Value>(_ body: () throws -> Value) rethrows -> Value {
    lock.lock()
    defer { lock.unlock() }
    return try body()
  }
}
