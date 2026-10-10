// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CryptoKit
import Foundation

extension PairRecord {
  /// The key this pairing derives for `info`, or `nil` for a degenerate
  /// agreement.
  internal func pairKey(info: Data) -> SymmetricKey? {
    PairKeys.derive(
      pairIdentifier: pairIdentifier,
      localStaticPrivate: localStaticPrivate,
      remoteStaticPublic: remoteStaticPublic,
      info: info)
  }
}
