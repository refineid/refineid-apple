// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

/// The short-Weierstrass domain parameters of one curve, in the form the
/// arithmetic uses.
///
/// Built once per curve from its transcribed values; the Montgomery
/// constants and the coefficients in Montgomery form are derived here, so
/// nothing in the arithmetic recomputes them.
public struct CurveDomainParameters: Sendable {
  /// The coefficient three of the tangent slope `(3 * x^2 + A) / (2 * y)`
  /// a point doubling takes.
  private static let tangentCoefficient: UInt64 = 3

  /// The field prime `p`.
  internal let prime: U384

  /// The field arithmetic modulo `p`.
  internal let field: MontgomeryDomain

  /// `A` of `y^2 = x^3 + A*x + B`, in Montgomery form.
  internal let montgomeryA: U384

  /// `B` of `y^2 = x^3 + A*x + B`, in Montgomery form.
  internal let montgomeryB: U384

  /// Three, in Montgomery form.
  internal let montgomeryThree: U384

  /// The base point's affine coordinates.
  internal let generatorX: U384
  internal let generatorY: U384

  /// The order `n` of the subgroup `G` generates.
  internal let order: U384

  /// The width of one coordinate, and of one scalar, in bytes.
  internal let coordinateByteCount: Int

  internal init(
    prime: U384,
    coefficientA: U384,
    coefficientB: U384,
    generatorX: U384,
    generatorY: U384,
    order: U384,
    coordinateByteCount: Int
  ) {
    let domain = MontgomeryDomain(prime: prime)
    self.prime = prime
    self.field = domain
    self.montgomeryA = domain.lifted(coefficientA)
    self.montgomeryB = domain.lifted(coefficientB)
    self.montgomeryThree = domain.lifted(U384(Self.tangentCoefficient))
    self.generatorX = generatorX
    self.generatorY = generatorY
    self.order = order
    self.coordinateByteCount = coordinateByteCount
  }
}
