// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

#if REFINEID_STREAM_TRANSPORT
  import Network
#endif

/// A custodian a requester found in pairing mode.
///
/// Over the nearby peer framework the framework finds the custodian itself,
/// so a requester has the one endpoint it names.
internal struct PairingEndpoint: Equatable, Sendable {
  #if REFINEID_STREAM_TRANSPORT
    /// A published service carrying the pairing attributes.
    internal let service: NWEndpoint
  #endif
}
