// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

/// An element of the prime field a ``PaceCurve`` is defined over, held in
/// Montgomery form.
///
/// The arithmetic is the curve's ``MontgomeryDomain``; this type only
/// keeps a residue and its curve together, so an element of one field can
/// never be combined with an element of another.
///
/// Deliberately not constant-time, like the domain it uses.
internal struct CurveFieldElement<Curve: PaceCurve>: Equatable, Sendable {
  /// Zero.
  internal static var zero: Self { Self(montgomery: U384.zero) }

  /// One, which in Montgomery form is `R mod p`.
  internal static var one: Self { Self(montgomery: Curve.parameters.field.one) }

  /// Three, the coefficient the tangent slope of a curve doubling needs.
  internal static var three: Self { Self(montgomery: Curve.parameters.montgomeryThree) }

  /// The field's arithmetic.
  private static var field: MontgomeryDomain {
    Curve.parameters.field
  }

  /// The residue in Montgomery form.
  internal let montgomery: U384

  /// True when this is the zero element.
  internal var isZero: Bool {
    montgomery.isZero
  }

  /// Lifts a value into the field, reducing it modulo `p`.
  internal init(_ value: U384) {
    montgomery = Self.field.lifted(value)
  }

  /// The element whose Montgomery representation is `montgomery`.
  internal init(montgomery: U384) {
    self.montgomery = montgomery
  }

  /// The canonical residue in `[0, p)`.
  internal func value() -> U384 {
    Self.field.canonical(montgomery)
  }

  /// The sum of this element and `other`.
  internal func adding(_ other: Self) -> Self {
    Self(montgomery: Self.field.add(montgomery, other.montgomery))
  }

  /// This element less `other`.
  internal func subtracting(_ other: Self) -> Self {
    Self(montgomery: Self.field.subtract(montgomery, other.montgomery))
  }

  /// The additive inverse.
  internal func negated() -> Self {
    Self(montgomery: Self.field.negate(montgomery))
  }

  /// The product of this element and `other`.
  internal func multiplied(by other: Self) -> Self {
    Self(montgomery: Self.field.multiply(montgomery, other.montgomery))
  }

  /// This element squared.
  internal func squared() -> Self {
    Self(montgomery: Self.field.multiply(montgomery, montgomery))
  }

  /// The multiplicative inverse, or nil for zero.
  ///
  /// Zero has no inverse, so the caller has to say what a zero denominator
  /// means; on a curve it means the point at infinity.
  internal func inverted() -> Self? {
    guard let inverse = Self.field.inverse(ofCanonical: value()) else { return nil }
    return Self(inverse)
  }
}
