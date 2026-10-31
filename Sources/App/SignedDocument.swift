// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// A finished signature held in memory until it is written.
internal struct SignedDocument: Sendable {
  /// The signed bytes.
  internal let bytes: Data

  /// The best signature time (ETSI EN 319 102-1 clause 5.5): the
  /// generation time of the signature timestamp, or the clock for a
  /// signature that carries none.
  internal let bestSignatureTime: Date

  /// A signature named by its signature timestamp.
  internal init(bytes: Data, signatureTimestampTime: Date) {
    self.bytes = bytes
    self.bestSignatureTime = signatureTimestampTime
  }

  /// A signature that carries no timestamp, named by the clock.
  internal init(untimestamped bytes: Data, clock: Date) {
    self.bytes = bytes
    self.bestSignatureTime = clock
  }
}
