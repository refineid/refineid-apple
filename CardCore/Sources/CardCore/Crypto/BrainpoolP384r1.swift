// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

/// The brainpoolP384r1 elliptic curve, RFC 5639 section 3.6.
///
/// The domain parameters live in `BrainpoolP384r1Values` as limb literals;
/// this type gives them curve meaning and provides scalar multiplication.
/// PACE on the FINEID card uses this curve for the ephemeral key agreement
/// and the generic mapping, and CryptoKit offers no Brainpool curve, so the
/// arithmetic is ours.
///
/// Scalar multiplication is double-and-add and is not constant-time. The
/// scalars it consumes are the ephemeral, single-use PACE keys, matching the
/// stated posture of the Rust reference implementation; it must not be given
/// a long-lived private key.
///
/// Provenance: lifted from the RefineID iOS browser donor
/// `Sources/RefineIDBrowserKit/Crypto/BrainpoolP384.swift`.
public enum BrainpoolP384r1 {
  /// A curve point in Jacobian coordinates, where the represented affine
  /// point is `(X / Z^2, Y / Z^3)` and `Z == 0` means infinity.
  ///
  /// Scalar multiplication repeatedly adds the same affine point, so mixed
  /// Jacobian-affine addition saves several field operations over general
  /// Jacobian addition. The formulas are from the Explicit-Formulas Database:
  /// https://www.hyperelliptic.org/EFD/g1p/auto-shortw-jacobian.html
  internal struct JacobianPoint {
    /// The additive identity.
    internal static let infinity = Self(
      horizontal: .zero,
      vertical: .one,
      scale: .zero
    )

    /// The Jacobian `X` coordinate.
    private let horizontal: FieldP384

    /// The Jacobian `Y` coordinate.
    private let vertical: FieldP384

    /// The Jacobian `Z` coordinate.
    private let scale: FieldP384

    /// Whether this is the point at infinity.
    private var isInfinity: Bool {
      scale.isZero
    }

    /// A point whose coordinates are already in the field.
    private init(horizontal: FieldP384, vertical: FieldP384, scale: FieldP384) {
      self.horizontal = horizontal
      self.vertical = vertical
      self.scale = scale
    }

    /// Lifts an affine point into Jacobian coordinates.
    private init?(_ point: BrainpoolPoint) {
      guard
        let affineHorizontal = point.affineX,
        let affineVertical = point.affineY
      else {
        return nil
      }
      self.init(
        horizontal: FieldP384(affineHorizontal),
        vertical: FieldP384(affineVertical),
        scale: .one
      )
    }

    /// Two times a field element.
    private static func twice(_ value: FieldP384) -> FieldP384 {
      value.adding(value)
    }

    /// Four times a field element.
    private static func fourTimes(_ value: FieldP384) -> FieldP384 {
      twice(twice(value))
    }

    /// Eight times a field element.
    private static func eightTimes(_ value: FieldP384) -> FieldP384 {
      twice(fourTimes(value))
    }

    /// This point added to itself without a field inversion.
    ///
    /// Formula `dbl-2007-bl` from the Explicit-Formulas Database, including
    /// the general curve coefficient `A`.
    internal func doubled() -> Self {
      guard !isInfinity, !vertical.isZero else { return .infinity }

      let horizontalSquared = horizontal.squared()
      let verticalSquared = vertical.squared()
      let verticalFourth = verticalSquared.squared()
      let scaleSquared = scale.squared()

      let sumSquared = horizontal.adding(verticalSquared).squared()
      let horizontalContribution = Self.twice(
        sumSquared.subtracting(horizontalSquared).subtracting(verticalFourth)
      )
      let tangent = horizontalSquared.multiplied(by: FieldP384.three)
        .adding(
          BrainpoolP384r1.coefficientA.multiplied(by: scaleSquared.squared())
        )

      let resultHorizontal = tangent.squared()
        .subtracting(Self.twice(horizontalContribution))
      let resultVertical =
        tangent
        .multiplied(by: horizontalContribution.subtracting(resultHorizontal))
        .subtracting(Self.eightTimes(verticalFourth))
      let verticalWithScale = vertical.adding(scale)
      let resultScale = verticalWithScale.squared()
        .subtracting(verticalSquared)
        .subtracting(scaleSquared)

      return Self(
        horizontal: resultHorizontal,
        vertical: resultVertical,
        scale: resultScale
      )
    }

    /// This Jacobian point plus an affine point without a field inversion.
    ///
    /// Formula `madd-2007-bl` from the Explicit-Formulas Database. The
    /// equality cases are handled explicitly because the generic formula
    /// produces `Z == 0` for both equal and inverse points.
    internal func adding(_ point: BrainpoolPoint) -> Self {
      guard let affineHorizontal = point.affineX, let affineVertical = point.affineY else {
        return self
      }
      guard !isInfinity else {
        return Self(point) ?? .infinity
      }

      let scaleSquared = scale.squared()
      let liftedHorizontal = FieldP384(affineHorizontal).multiplied(by: scaleSquared)
      let liftedVertical = FieldP384(affineVertical)
        .multiplied(by: scale)
        .multiplied(by: scaleSquared)
      let horizontalDifference = liftedHorizontal.subtracting(horizontal)
      let verticalDifference = liftedVertical.subtracting(vertical)

      guard !horizontalDifference.isZero else {
        return verticalDifference.isZero ? doubled() : .infinity
      }

      let horizontalDifferenceSquared = horizontalDifference.squared()
      let fourHorizontalDifferenceSquared = Self.fourTimes(horizontalDifferenceSquared)
      let horizontalDifferenceCubed = horizontalDifference.multiplied(
        by: fourHorizontalDifferenceSquared
      )
      let doubledVerticalDifference = Self.twice(verticalDifference)
      let scaledHorizontal = horizontal.multiplied(by: fourHorizontalDifferenceSquared)

      let resultHorizontal = doubledVerticalDifference.squared()
        .subtracting(horizontalDifferenceCubed)
        .subtracting(Self.twice(scaledHorizontal))
      let resultVertical =
        doubledVerticalDifference
        .multiplied(by: scaledHorizontal.subtracting(resultHorizontal))
        .subtracting(
          Self.twice(vertical.multiplied(by: horizontalDifferenceCubed))
        )
      let scaleWithDifference = scale.adding(horizontalDifference)
      let resultScale = scaleWithDifference.squared()
        .subtracting(scaleSquared)
        .subtracting(horizontalDifferenceSquared)

      return Self(
        horizontal: resultHorizontal,
        vertical: resultVertical,
        scale: resultScale
      )
    }

    /// Converts to the public affine representation, paying one inversion.
    internal func affinePoint() -> BrainpoolPoint {
      guard !isInfinity, let inverseScale = scale.inverted() else {
        return .infinity
      }
      let inverseScaleSquared = inverseScale.squared()
      let affineHorizontal = horizontal.multiplied(by: inverseScaleSquared)
      let affineVertical =
        vertical
        .multiplied(by: inverseScaleSquared)
        .multiplied(by: inverseScale)
      return BrainpoolPoint(
        onCurveX: affineHorizontal.value(),
        onCurveY: affineVertical.value()
      )
    }
  }

  /// The field prime `p`.
  internal static let prime = BrainpoolP384r1Values.prime

  /// The curve equation coefficient `A`, as a field element.
  internal static let coefficientA = FieldP384(BrainpoolP384r1Values.coefficientA)

  /// The curve equation coefficient `B`, as a field element.
  internal static let coefficientB = FieldP384(BrainpoolP384r1Values.coefficientB)

  /// The base point `G`.
  public static let generator = BrainpoolPoint(
    onCurveX: BrainpoolP384r1Values.generatorX,
    onCurveY: BrainpoolP384r1Values.generatorY
  )

  /// The order `n` of the subgroup generated by `G`.
  public static let order = BrainpoolP384r1Values.order

  /// The cofactor `h`, which is 1 for this curve.
  public static let cofactor = BrainpoolP384r1Values.cofactor

  /// `scalar * point`, by double-and-add from the scalar's highest set bit.
  ///
  /// Intermediate points use Jacobian coordinates. Affine addition and
  /// doubling each need a field inversion; keeping `Z` avoids hundreds of
  /// those inversions and pays for exactly one when the final point is
  /// converted back to the public affine representation.
  ///
  /// A zero scalar gives the point at infinity.
  public static func multiply(_ point: BrainpoolPoint, by scalar: U384) -> BrainpoolPoint {
    guard let highestBit = scalar.highestSetBitIndex, !point.isInfinity else {
      return .infinity
    }
    var result = JacobianPoint.infinity
    for index in stride(from: highestBit, through: 0, by: -1) {
      result = result.doubled()
      if scalar.bit(at: index) {
        result = result.adding(point)
      }
    }
    return result.affinePoint()
  }

  /// `scalar * G`, the public point of a private scalar.
  public static func multiplyGenerator(by scalar: U384) -> BrainpoolPoint {
    multiply(Self.generator, by: scalar)
  }
}
