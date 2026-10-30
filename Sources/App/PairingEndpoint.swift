// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation
import Network

/// A custodian a requester found in pairing mode.
internal struct PairingEndpoint: Equatable, Sendable {
  /// A published service carrying the pairing attributes.
  internal let service: NWEndpoint
}
