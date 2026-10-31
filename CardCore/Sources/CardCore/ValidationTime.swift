// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// The time a signature's chain and revocation are judged at
/// (EN 319 102-1 clause 5.6.2).
public enum ValidationTime: Sendable, Equatable {
  /// The verifier's clock, without a proof of existence.
  case currentClock(Date)

  /// The earliest proof of existence.
  case proven(ProvenTime)

  /// The instant either names.
  public var date: Date {
    switch self {
    case .proven(let proven):
      proven.date

    case .currentClock(let now):
      now
    }
  }

  /// The proof of existence, when there is one.
  public var proofOfExistence: Date? {
    guard case .proven(let proven) = self else { return nil }
    return proven.date
  }
}
