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
  /// The range one scalar is drawn from: `[1, order)`, in `byteCount`
  /// bytes, the width of the curve's scalars.
  internal struct Range {
    internal let order: U384
    internal let byteCount: Int
  }

  /// The shipping source: rejection sampling over the platform CSPRNG.
  ///
  /// Computed rather than stored because the type wraps a closure and is
  /// therefore not `Sendable`; a fresh value costs nothing and keeps the
  /// module free of shared mutable state.
  public static var secureRandom: Self {
    Self(drawing: Self.randomScalar(in:))
  }

  /// The underlying generator.
  private let produce: (Range) -> U384

  /// Wraps a generator of scalars in `[1, n)` of the curve the run uses.
  ///
  /// The caller owns the guarantee that values are in range and
  /// unpredictable; `secureRandom` is the only implementation that has it.
  public init(producing: @escaping () -> U384) {
    self.produce = { _ in producing() }
  }

  private init(drawing: @escaping (Range) -> U384) {
    self.produce = drawing
  }

  /// A uniform scalar in `[1, n)` from the platform CSPRNG.
  ///
  /// `SystemRandomNumberGenerator` is the platform cryptographic random
  /// source on Apple platforms. A candidate is the scalar width in random
  /// bytes; candidates at or above the group order, and the zero
  /// candidate, are discarded rather than reduced, so the result is
  /// uniform on the interval.
  private static func randomScalar(in range: Range) -> U384 {
    var generator = SystemRandomNumberGenerator()
    while true {
      let bytes = Data(
        (0..<range.byteCount).map { _ in UInt8.random(in: .min ... .max, using: &generator) })
      if let candidate = U384(bigEndianBytes: bytes), !candidate.isZero, candidate < range.order {
        return candidate
      }
    }
  }

  /// The next ephemeral scalar for a curve of order `order`.
  internal func nextScalar(below order: U384, byteCount: Int) -> U384 {
    produce(Range(order: order, byteCount: byteCount))
  }
}
