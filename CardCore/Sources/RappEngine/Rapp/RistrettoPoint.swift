// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CryptoKit
import Foundation

// swiftlint:disable no_magic_numbers

/// Point in Ristretto255 / Curve25519 in extended Edwards coordinates: (coordX:coordY:coordZ:coordT).
internal struct RistrettoPoint: Equatable, Sendable {
  internal static let identity = Self(
    coordX: .zero,
    coordY: .one,
    coordZ: .one,
    coordT: .zero
  )

  internal var coordX: FieldElement51
  internal var coordY: FieldElement51
  internal var coordZ: FieldElement51
  internal var coordT: FieldElement51

  internal static func + (lhs: Self, rhs: Self) -> Self {
    let termX1 = lhs.coordX
    let termY1 = lhs.coordY
    let termZ1 = lhs.coordZ
    let termT1 = lhs.coordT

    let termX2 = rhs.coordX
    let termY2 = rhs.coordY
    let termZ2 = rhs.coordZ
    let termT2 = rhs.coordT

    let termA = (termY1 - termX1) * (termY2 - termX2)
    let termB = (termY1 + termX1) * (termY2 + termX2)
    let termC = termT1 * (FieldElement51.edwardsD * 2) * termT2
    let termD = termZ1 * 2 * termZ2
    let termE = termB - termA
    let termF = termD - termC
    let termG = termD + termC
    let termH = termB + termA

    return Self(
      coordX: termE * termF,
      coordY: termG * termH,
      coordZ: termF * termG,
      coordT: termE * termH
    )
  }

  internal static func += (lhs: inout Self, rhs: Self) {
    lhs = lhs + rhs
  }

  internal static func == (lhs: Self, rhs: Self) -> Bool {
    let x1y2 = lhs.coordX * rhs.coordY
    let y1x2 = lhs.coordY * rhs.coordX
    let x1x2 = lhs.coordX * rhs.coordX
    let y1y2 = lhs.coordY * rhs.coordY
    return (x1y2 == y1x2) || (y1y2 == x1x2)
  }

  /// Decode canonical 32-byte Ristretto encoding (RFC 9496 Section 4.3.1).
  internal static func decompress(_ bytes32: Data) -> Self? {
    guard bytes32.count == 32 else { return nil }
    let varS = FieldElement51(bytes: bytes32)
    if varS.canonicalBytes() != bytes32 || varS.isNegative {
      return nil
    }

    let squareS = varS.square()
    let termU1 = FieldElement51.one - squareS
    let termU2 = FieldElement51.one + squareS
    let termU2Sq = termU2.square()
    let termV = -(FieldElement51.edwardsD * termU1.square()) - termU2Sq

    let (wasSquare, invsqrtVal) = FieldElement51.sqrtRatioI(elemU: .one, elemV: termV * termU2Sq)
    let denX = invsqrtVal * termU2
    let denY = invsqrtVal * denX * termV

    var pointX = (varS * 2) * denX
    if pointX.isNegative {
      pointX = -pointX
    }
    let pointY = termU1 * denY
    let pointT = pointX * pointY

    if !wasSquare || pointT.isNegative || pointY.isZero {
      return nil
    }

    return Self(coordX: pointX, coordY: pointY, coordZ: .one, coordT: pointT)
  }

  /// Ristretto-flavored Elligator map (RFC 9496 Section 4.3.4 MAP).
  internal static func elligator(_ bytes32: Data) -> Self {
    var rawArr = [UInt8](bytes32)
    guard rawArr.count == 32 else { return .identity }
    rawArr[31] &= 127
    let stepR0 = FieldElement51(bytes: Data(rawArr))
    let stepR = FieldElement51.sqrtM1 * stepR0.square()
    let stepNs = (stepR + .one) * FieldElement51.oneMinusDSq
    let stepD =
      (-FieldElement51.one - FieldElement51.edwardsD * stepR) * (stepR + FieldElement51.edwardsD)

    let (nsDIsSquare, candidateS) = FieldElement51.sqrtRatioI(elemU: stepNs, elemV: stepD)
    var stepS = candidateS
    var stepSPrime = stepS * stepR0
    if !stepSPrime.isNegative {
      stepSPrime = -stepSPrime
    }

    var stepC = FieldElement51.minusOne
    if !nsDIsSquare {
      stepS = stepSPrime
      stepC = stepR
    }

    let stepNt = stepC * (stepR - .one) * FieldElement51.dMinusOneSq - stepD
    let stepSSq = stepS.square()

    let pointX = (stepS * 2) * stepD
    let pointZ = stepNt * FieldElement51.sqrtAdMinusOne
    let pointY = FieldElement51.one - stepSSq
    let pointT = FieldElement51.one + stepSSq

    return Self(
      coordX: pointX * pointT,
      coordY: pointY * pointZ,
      coordZ: pointZ * pointT,
      coordT: pointX * pointY
    )
  }

  /// Derive uniform group element from 64 uniform bytes (RFC 9496 Section 4.3.4).
  internal static func fromUniformBytes(_ bytes64: Data) -> Self {
    precondition(bytes64.count == 64, "fromUniformBytes requires 64 bytes")
    let pointP1 = elligator(bytes64.prefix(32))
    let pointP2 = elligator(bytes64.suffix(32))
    return pointP1 + pointP2
  }

  internal func double() -> Self {
    let termA = coordX.square()
    let termB = coordY.square()
    let termC = coordZ.square() * 2
    let termD = -termA
    let termE = (coordX + coordY).square() - termA - termB
    let termG = termD + termB
    let termF = termG - termC
    let termH = termD - termB

    return Self(
      coordX: termE * termF,
      coordY: termG * termH,
      coordZ: termF * termG,
      coordT: termE * termH
    )
  }

  /// Scalar multiplication by a 32-byte little-endian scalar.
  internal func scalarMul(_ scalarBytes: Data) -> Self {
    var result = Self.identity
    for byteVal in scalarBytes.reversed() {
      for bitIndex in stride(from: 7, through: 0, by: -1) {
        result = result.double()
        if ((byteVal >> bitIndex) & 1) == 1 {
          result += self
        }
      }
    }
    return result
  }

  /// Compress to canonical 32-byte Ristretto encoding (RFC 9496 Section 4.3.2).
  internal func compress() -> Data {
    var curX = coordX
    var curY = coordY
    let curZ = coordZ
    let curT = coordT

    let termU1 = (curZ + curY) * (curZ - curY)
    let termU2 = curX * curY
    let (_, invsqrtVal) = FieldElement51.sqrtRatioI(elemU: .one, elemV: termU1 * termU2.square())
    let den1 = invsqrtVal * termU1
    let den2 = invsqrtVal * termU2
    let zInv = den1 * den2 * curT
    var denInv = den2

    let pointIx = curX * FieldElement51.sqrtM1
    let pointIy = curY * FieldElement51.sqrtM1
    let enchantedDen = den1 * FieldElement51.invsqrtAMinusD

    let rotate = (curT * zInv).isNegative
    if rotate {
      curX = pointIy
      curY = pointIx
      denInv = enchantedDen
    }

    if (curX * zInv).isNegative {
      curY = -curY
    }

    var varS = denInv * (curZ - curY)
    if varS.isNegative {
      varS = -varS
    }

    return varS.canonicalBytes()
  }
}

// swiftlint:enable no_magic_numbers
