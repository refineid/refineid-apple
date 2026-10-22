// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// The card the custodian holds (RAPP v26.10.22 §8.4 items 1 and 2).
public enum RappCardPresence: Equatable, Sendable {
  /// The custodian holds no card.
  case absent
  /// The custodian holds a card; the fingerprint of its authentication
  /// certificate.
  case present(RappCertificateFingerprint)
}
