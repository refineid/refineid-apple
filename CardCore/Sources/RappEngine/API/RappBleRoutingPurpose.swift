// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// Why a central opened a `fi.refineid.rapp.ble.v1` connection: the one
/// plaintext routing preamble of `Phase::Routing` (RAPP v26.10.9 §5.2).
public enum RappBleRoutingPurpose: Equatable, Sendable {
  /// Open a pairing ceremony against the custodian's live offer.
  case pairing
  /// Reach the stored pairing this rendezvous token names.
  case session(rendezvousToken: Data)

  /// Reads a preamble, or nil for anything §5.2 calls invalid: unknown
  /// purpose, malformed CBOR, a token of the wrong size, or an oversized
  /// frame.
  public init?(preamble: Data) {
    switch try? BleRendezvous.decode(preamble) {
    case .pairing:
      self = .pairing

    case .session(let token):
      self = .session(rendezvousToken: token)

    case nil:
      return nil
    }
  }

  /// The preamble frame announcing this purpose.
  ///
  /// - Throws: ``RappBindingError/InvalidInput`` for a session token that
  ///   is not 16 bytes.
  public func preamble() throws -> Data {
    switch self {
    case .pairing:
      return rappBlePairingPreamble()

    case .session(let token):
      return try rappBleSessionPreamble(rendezvousToken: token)
    }
  }
}
