// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// Where PACE gets its two ephemeral private scalars.
///
/// PACE draws one scalar for the generic mapping and one for the key
/// agreement on the mapped generator. Both are single-use and both must be
/// unpredictable, so the shipping source is the platform CSPRNG. The
/// indirection exists so a test can drive the protocol with fixed scalars
/// and check that terminal and card derive the same session keys -- an
/// establishment run is otherwise unreproducible and therefore unverifiable
/// off hardware.
///
/// Injecting a deterministic source into a real session would destroy the
/// security of that session. Nothing on the shipping path constructs
/// anything but `secureRandom`.
///
/// Provenance: replaces the `nextScalar` closure parameter and
/// `PACE.randomScalar` of the RefineID iOS browser donor
/// `Sources/RefineIDBrowserKit/Card/Pace.swift`.
public struct PaceEphemeralScalarSource {
  /// The shipping source: rejection sampling over the platform CSPRNG.
  ///
  /// Computed rather than stored because the type wraps a closure and is
  /// therefore not `Sendable`; a fresh value costs nothing and keeps the
  /// module free of shared mutable state.
  public static var secureRandom: Self {
    Self(producing: Self.randomScalar)
  }

  /// The underlying generator.
  private let produce: () -> U384

  /// Wraps a generator of scalars in `[1, n)`.
  ///
  /// The caller owns the guarantee that values are in range and
  /// unpredictable; `secureRandom` is the only implementation that has it.
  public init(producing: @escaping () -> U384) {
    self.produce = producing
  }

  /// A uniform scalar in `[1, n)` from the platform CSPRNG.
  ///
  /// `SystemRandomNumberGenerator` is the platform cryptographic random
  /// source on Apple platforms. Candidates at or above the group order, and
  /// the zero candidate, are discarded rather than reduced, so the result
  /// is uniform on the interval; the rejection probability is negligible
  /// because the brainpoolP384r1 order is just below `2^384`.
  private static func randomScalar() -> U384 {
    var generator = SystemRandomNumberGenerator()
    while true {
      let candidate = U384(
        limb0: generator.next(),
        limb1: generator.next(),
        limb2: generator.next(),
        limb3: generator.next(),
        limb4: generator.next(),
        limb5: generator.next()
      )
      if !candidate.isZero, candidate < BrainpoolP384r1.order {
        return candidate
      }
    }
  }

  /// The next ephemeral scalar.
  internal func nextScalar() -> U384 {
    produce()
  }
}
