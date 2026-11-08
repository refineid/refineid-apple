// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation
import Network

/// A custodian a requester found in pairing mode, on the transport it was
/// found on (RAPP v26.11.8 §4.2, "Trying Each Custodian in Pairing Mode"
/// item 1).
internal enum PairingEndpoint: Equatable, Sendable {
  /// A peripheral advertising the RAPP service, by the identifier Core
  /// Bluetooth assigns it on this device; it is in pairing mode if it
  /// serves an offer on a pairing connection.
  case bluetooth(UUID)
  /// A published service carrying the pairing attributes.
  case stream(NWEndpoint)
}
