// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CryptoKit
import Foundation

extension PairRecord {
  /// The key this pairing derives for `info`, or `nil` when it has none.
  ///
  /// A degenerate agreement has none, and so has a pairing whose storage
  /// was never confirmed: such a pairing routes, announces, and withdraws
  /// nothing (RAPP v26.10.18 §4.3 item 4). The revocation key is derived
  /// separately, because an unconfirmed record is exactly what gets
  /// revoked.
  internal func pairKey(info: Data) -> SymmetricKey? {
    guard storageConfirmed else { return nil }
    return revocableKey(info: info)
  }

  /// The key this pairing derives for `info` whether or not its storage
  /// was confirmed, or `nil` for a degenerate agreement.
  internal func revocableKey(info: Data) -> SymmetricKey? {
    PairKeys.derive(
      pairIdentifier: pairIdentifier,
      localStaticPrivate: localStaticPrivate,
      remoteStaticPublic: remoteStaticPublic,
      info: info)
  }
}
