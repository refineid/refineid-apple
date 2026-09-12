// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// A point on the brainpoolP384r1 curve in affine coordinates.
///
/// Either the point at infinity, or a pair of canonical coordinates both
/// below the field prime and satisfying `y^2 = x^3 + A*x + B`. The public
/// initializer is the gate: a pair of arbitrary 384-bit integers cannot
/// become a point without passing the curve equation, so nothing downstream
/// has to re-check what it was handed.
///
/// Provenance: lifted from the RefineID iOS browser donor
/// `Sources/RefineIDBrowserKit/Crypto/BrainpoolP384.swift`.
public struct BrainpoolPoint: Equatable, Sendable {
  /// The point at infinity, the additive identity of the curve group.
  public static let infinity = Self(affine: nil)

  /// The number of coordinates an uncompressed encoding carries.
  private static let uncompressedCoordinateCount = 2

  /// The length of the SEC1 uncompressed encoding, `04 || X || Y`.
  public static let uncompressedByteCount =
    U384.byteCount * uncompressedCoordinateCount + 1

  /// The affine coordinates, or nil for the point at infinity.
  private let affine: (affineX: U384, affineY: U384)?

  /// True when this is the point at infinity.
  public var isInfinity: Bool {
    affine == nil
  }

  /// The affine `x` coordinate, or nil at infinity.
  public var affineX: U384? {
    affine?.affineX
  }

  /// The affine `y` coordinate, or nil at infinity.
  public var affineY: U384? {
    affine?.affineY
  }

  /// The point with these coordinates, or nil when they are not a canonical
  /// point of this curve.
  ///
  /// Rejects a coordinate at or above the field prime, which is a
  /// non-canonical encoding, and any pair that is off the curve.
  public init?(affineX: U384, affineY: U384) {
    guard affineX < BrainpoolP384r1.prime, affineY < BrainpoolP384r1.prime else {
      return nil
    }
    let candidate = Self(onCurveX: affineX, onCurveY: affineY)
    guard candidate.isOnCurve() else { return nil }
    self = candidate
  }

  /// The point with coordinates the caller already knows to be on the curve.
  ///
  /// Used by the curve arithmetic, whose outputs are on the curve by
  /// construction, and by the generator constant; re-deriving the curve
  /// equation for every intermediate would multiply the cost of a scalar
  /// multiplication several times over.
  internal init(onCurveX: U384, onCurveY: U384) {
    affine = (onCurveX, onCurveY)
  }

  /// The point with the given optional coordinates, nil meaning infinity.
  private init(affine: (affineX: U384, affineY: U384)?) {
    self.affine = affine
  }

  /// Two points are equal when both are at infinity or both coordinates
  /// match.
  public static func == (lhs: Self, rhs: Self) -> Bool {
    guard let left = lhs.affine else { return rhs.affine == nil }
    guard let right = rhs.affine else { return false }
    return left.affineX == right.affineX && left.affineY == right.affineY
  }

  /// The point carried by a SEC1 uncompressed encoding `04 || X || Y`, or nil
  /// when the input is the wrong length, carries another point form, uses a
  /// non-canonical coordinate, or is off the curve.
  public static func decodeUncompressed(_ encoded: Data) -> Self? {
    guard encoded.count == Self.uncompressedByteCount,
      encoded.first == Sec1Values.uncompressedPointTag
    else {
      return nil
    }
    let coordinates = Data(encoded.dropFirst())
    guard let horizontal = U384(bigEndianBytes: Data(coordinates.prefix(U384.byteCount))),
      let vertical = U384(bigEndianBytes: Data(coordinates.dropFirst(U384.byteCount)))
    else {
      return nil
    }
    return Self(affineX: horizontal, affineY: vertical)
  }

  /// True when the point satisfies `y^2 = x^3 + A*x + B` over GF(p).
  ///
  /// The point at infinity trivially belongs to the group, so it answers
  /// true.
  public func isOnCurve() -> Bool {
    guard let point = affine else { return true }
    let horizontal = FieldP384(point.affineX)
    let vertical = FieldP384(point.affineY)
    let left = vertical.squared()
    let cubed = horizontal.squared().multiplied(by: horizontal)
    let linear = BrainpoolP384r1.coefficientA.multiplied(by: horizontal)
    let right = cubed.adding(linear).adding(BrainpoolP384r1.coefficientB)
    return left == right
  }

  /// The additive inverse `(x, -y)`.
  public func negated() -> Self {
    guard let point = affine else { return .infinity }
    return Self(
      onCurveX: point.affineX, onCurveY: FieldP384(point.affineY).negated().value())
  }

  /// This point added to itself, by the affine tangent formula.
  ///
  /// A point of order two has a vertical tangent, so its double is the point
  /// at infinity; that shows up here as a zero denominator.
  public func doubled() -> Self {
    guard let point = affine else { return .infinity }
    let horizontal = FieldP384(point.affineX)
    let vertical = FieldP384(point.affineY)
    guard let inverseDenominator = vertical.adding(vertical).inverted() else {
      return .infinity
    }
    let tangentNumerator = horizontal.squared().multiplied(by: FieldP384.three)
    let slope = tangentNumerator.adding(BrainpoolP384r1.coefficientA)
      .multiplied(by: inverseDenominator)
    let doubledX = slope.squared().subtracting(horizontal).subtracting(horizontal)
    let doubledY = slope.multiplied(by: horizontal.subtracting(doubledX)).subtracting(vertical)
    return Self(onCurveX: doubledX.value(), onCurveY: doubledY.value())
  }

  /// The group sum of this point and `other`, by the affine chord formula.
  ///
  /// Falls back to doubling when the points coincide and to infinity when
  /// they are inverses.
  public func adding(_ other: Self) -> Self {
    guard let left = affine else { return other }
    guard let right = other.affine else { return self }
    guard left.affineX != right.affineX else {
      return left.affineY == right.affineY ? doubled() : .infinity
    }
    let leftX = FieldP384(left.affineX)
    let leftY = FieldP384(left.affineY)
    let rightX = FieldP384(right.affineX)
    let rightY = FieldP384(right.affineY)
    guard let inverseDenominator = rightX.subtracting(leftX).inverted() else {
      return .infinity
    }
    let slope = rightY.subtracting(leftY).multiplied(by: inverseDenominator)
    let sumX = slope.squared().subtracting(leftX).subtracting(rightX)
    let sumY = slope.multiplied(by: leftX.subtracting(sumX)).subtracting(leftY)
    return Self(onCurveX: sumX.value(), onCurveY: sumY.value())
  }

  /// The SEC1 uncompressed encoding `04 || X || Y`, or nil at infinity, which
  /// has no such encoding.
  public func encodeUncompressed() -> Data? {
    guard let point = affine else { return nil }
    var encoded = Data([Sec1Values.uncompressedPointTag])
    encoded.append(point.affineX.bigEndianBytes())
    encoded.append(point.affineY.bigEndianBytes())
    return encoded
  }
}
