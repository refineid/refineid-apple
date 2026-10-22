// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CryptoKit
import Foundation

extension PairRecord {
  /// The key this pairing derives for `info`, or `nil` when it has none.
  ///
  /// A degenerate agreement has none, and so has a pairing whose storage
  /// was never confirmed: such a pairing routes, announces, and withdraws
  /// nothing (RAPP v26.10.21 §4.3 item 4).
  internal func pairKey(info: Data) -> SymmetricKey? {
    guard storageConfirmed else { return nil }
    return PairKeys.derive(
      pairIdentifier: pairIdentifier,
      localStaticPrivate: localStaticPrivate,
      remoteStaticPublic: remoteStaticPublic,
      info: info)
  }
}
