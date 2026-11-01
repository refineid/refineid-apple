// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

/// A curve point in Jacobian coordinates, where the represented affine
/// point is `(X / Z^2, Y / Z^3)` and `Z == 0` means infinity.
///
/// Scalar multiplication repeatedly adds the same affine point, so mixed
/// Jacobian-affine addition saves several field operations over general
/// Jacobian addition. The formulas are from the Explicit-Formulas Database:
/// https://www.hyperelliptic.org/EFD/g1p/auto-shortw-jacobian.html
internal struct JacobianPoint<Curve: PaceCurve> {
  private typealias Element = CurveFieldElement<Curve>

  /// The additive identity.
  internal static var infinity: Self {
    Self(horizontal: .zero, vertical: .one, scale: .zero)
  }

  /// The Jacobian `X` coordinate.
  private let horizontal: Element

  /// The Jacobian `Y` coordinate.
  private let vertical: Element

  /// The Jacobian `Z` coordinate.
  private let scale: Element

  /// Whether this is the point at infinity.
  private var isInfinity: Bool {
    scale.isZero
  }

  /// A point whose coordinates are already in the field.
  private init(horizontal: Element, vertical: Element, scale: Element) {
    self.horizontal = horizontal
    self.vertical = vertical
    self.scale = scale
  }

  /// Lifts an affine point into Jacobian coordinates.
  private init?(_ point: CurvePoint<Curve>) {
    guard
      let affineHorizontal = point.affineX,
      let affineVertical = point.affineY
    else {
      return nil
    }
    self.init(
      horizontal: Element(affineHorizontal),
      vertical: Element(affineVertical),
      scale: .one
    )
  }

  /// Two times a field element.
  private static func twice(_ value: Element) -> Element {
    value.adding(value)
  }

  /// Four times a field element.
  private static func fourTimes(_ value: Element) -> Element {
    twice(twice(value))
  }

  /// Eight times a field element.
  private static func eightTimes(_ value: Element) -> Element {
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
    let tangent = horizontalSquared.multiplied(by: .three)
      .adding(Curve.coefficientA.multiplied(by: scaleSquared.squared()))

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
  internal func adding(_ point: CurvePoint<Curve>) -> Self {
    guard let affineHorizontal = point.affineX, let affineVertical = point.affineY else {
      return self
    }
    guard !isInfinity else {
      return Self(point) ?? .infinity
    }

    let scaleSquared = scale.squared()
    let liftedHorizontal = Element(affineHorizontal).multiplied(by: scaleSquared)
    let liftedVertical = Element(affineVertical)
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
  internal func affinePoint() -> CurvePoint<Curve> {
    guard !isInfinity, let inverseScale = scale.inverted() else {
      return .infinity
    }
    let inverseScaleSquared = inverseScale.squared()
    let affineHorizontal = horizontal.multiplied(by: inverseScaleSquared)
    let affineVertical =
      vertical
      .multiplied(by: inverseScaleSquared)
      .multiplied(by: inverseScale)
    return CurvePoint(
      onCurveX: affineHorizontal.value(),
      onCurveY: affineVertical.value()
    )
  }
}
