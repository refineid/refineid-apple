// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// The custodian's operations of one session: one live at a time, and every
/// identifier used once.
///
/// Nothing outlives the session (RAPP v26.10.29 §8.1).
internal struct ProxyOperationEngine {
  /// The profiles the pairing granted; a request naming any other is
  /// refused before the holder is asked.
  internal let grantedProfiles: [ProfileName]

  internal var live: AuthorizationTransaction?

  internal var seen: Set<RappOperationIdentifier>

  /// An engine bound to exactly the profiles the pairing granted.
  internal init(grantedProfiles: [ProfileName]) {
    self.grantedProfiles = grantedProfiles
    self.live = nil
    self.seen = []
  }

  /// The live request the identifier names.
  internal func request(_ operationIdentifier: RappOperationIdentifier) -> OperationRequest? {
    guard let live, live.operationIdentifier == operationIdentifier else { return nil }
    return live.request
  }
}
