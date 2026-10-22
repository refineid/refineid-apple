// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// Why a BLE link was opened, as its plaintext routing preamble says
/// (RAPP v26.10.21 §5.2).
public enum RappBleRoutingPurpose: Equatable, Sendable {
  /// Run the pairing ceremony.
  case pairing
  /// Reach a stored pairing; the preamble carries the fresh routing that
  /// a ``RappSessionRouter`` resolves.
  case session(preamble: Data)

  /// The purpose a received preamble names, or `nil` for anything else.
  public init?(preamble: Data) {
    switch try? RoutingPreamble.decode(preamble, profile: RappBleGattProfile.name) {
    case .pairing:
      self = .pairing

    case .session:
      self = .session(preamble: preamble)

    case nil:
      return nil
    }
  }

  /// The preamble to send for this purpose.
  public func preamble() throws -> Data {
    switch self {
    case .pairing:
      return try rappPairingPreamble(transportProfile: RappBleGattProfile.name)

    case .session(let preamble):
      return preamble
    }
  }
}
