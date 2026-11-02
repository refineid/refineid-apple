// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CardCore
import CryptoKit
import Foundation
import Testing

/// Checks the NIST P-256 and P-384 arithmetic against CryptoKit.
///
/// The domain parameters are stored as little-endian limb literals, so a
/// mistranscribed limb would be invisible on inspection. CryptoKit is the
/// independent implementation: the public key it derives from a scalar is
/// that scalar times the generator, and the shared secret it agrees is the
/// x-coordinate of a scalar times another point. Equal answers for the
/// scalar one, for fixed full-width scalars and for random ones pin the
/// prime, the coefficients, the generator and the group law; `n * G` at
/// infinity pins the order.
@Suite
internal struct NistCurveTests {
  /// Labels the fixed scalars are hashed from.
  private static let scalarLabels = ["first", "second", "third", "fourth"]

  /// How many random scalars each run adds.
  private static let randomScalarCount = 4

  /// The scalar one.
  private static let one = U384.one

  /// The SEC1 encoding of `scalar * G` by this module.
  private static func encodedMultiple<Curve: PaceCurve>(
    _: Curve.Type, _ scalar: Data
  ) throws -> Data? {
    let value = try #require(U384(bigEndianBytes: scalar))
    return Curve.multiplyGenerator(by: value).encodeUncompressed()
  }

  /// Fixed full-width scalars below both orders: SHA-256 and SHA-384
  /// digests have a leading zero bit with probability one half, so the
  /// top byte is cleared to keep them in range.
  private static func fixedScalars(byteCount: Int) -> [Data] {
    scalarLabels.map { label in
      var digest =
        byteCount == SHA384.byteCount
        ? Data(SHA384.hash(data: Data(label.utf8)))
        : Data(SHA256.hash(data: Data(label.utf8)))
      digest[digest.startIndex] = 0
      return digest
    }
  }

  @Test
  internal func p256MultiplesMatchCryptoKitPublicKeys() throws {
    var scalars = Self.fixedScalars(byteCount: NistP256.coordinateByteCount)
    scalars.append(Self.one.bigEndianBytes().suffix(NistP256.coordinateByteCount))
    for _ in 0..<Self.randomScalarCount {
      scalars.append(P256.KeyAgreement.PrivateKey().rawRepresentation)
    }
    for scalar in scalars {
      let key = try P256.KeyAgreement.PrivateKey(rawRepresentation: scalar)
      #expect(try Self.encodedMultiple(NistP256.self, scalar) == key.publicKey.x963Representation)
    }
  }

  @Test
  internal func p384MultiplesMatchCryptoKitPublicKeys() throws {
    var scalars = Self.fixedScalars(byteCount: NistP384.coordinateByteCount)
    scalars.append(Self.one.bigEndianBytes())
    for _ in 0..<Self.randomScalarCount {
      scalars.append(P384.KeyAgreement.PrivateKey().rawRepresentation)
    }
    for scalar in scalars {
      let key = try P384.KeyAgreement.PrivateKey(rawRepresentation: scalar)
      #expect(try Self.encodedMultiple(NistP384.self, scalar) == key.publicKey.x963Representation)
    }
  }

  @Test
  internal func p256AgreementMatchesCryptoKit() throws {
    let ours = P256.KeyAgreement.PrivateKey()
    let theirs = P256.KeyAgreement.PrivateKey()
    let point = try #require(
      CurvePoint<NistP256>.decodeUncompressed(theirs.publicKey.x963Representation))
    let scalar = try #require(U384(bigEndianBytes: ours.rawRepresentation))
    let shared = try #require(NistP256.multiply(point, by: scalar).affineX)
    let expected = try ours.sharedSecretFromKeyAgreement(with: theirs.publicKey)
    #expect(
      CurvePoint<NistP256>.fieldBytes(shared) == expected.withUnsafeBytes { Data($0) })
  }

  @Test
  internal func p384AgreementMatchesCryptoKit() throws {
    let ours = P384.KeyAgreement.PrivateKey()
    let theirs = P384.KeyAgreement.PrivateKey()
    let point = try #require(
      CurvePoint<NistP384>.decodeUncompressed(theirs.publicKey.x963Representation))
    let scalar = try #require(U384(bigEndianBytes: ours.rawRepresentation))
    let shared = try #require(NistP384.multiply(point, by: scalar).affineX)
    let expected = try ours.sharedSecretFromKeyAgreement(with: theirs.publicKey)
    #expect(
      CurvePoint<NistP384>.fieldBytes(shared) == expected.withUnsafeBytes { Data($0) })
  }

  @Test
  internal func theOrderTimesTheGeneratorIsInfinity() {
    #expect(NistP256.multiplyGenerator(by: NistP256.order).isInfinity)
    #expect(NistP384.multiplyGenerator(by: NistP384.order).isInfinity)
  }

  @Test
  internal func theGeneratorsAreOnTheirCurves() {
    #expect(NistP256.generator.isOnCurve())
    #expect(NistP384.generator.isOnCurve())
  }

  @Test
  internal func encodingsHaveTheFieldWidthAndRoundTrip() throws {
    let p256 = try #require(NistP256.generator.encodeUncompressed())
    let p384 = try #require(NistP384.generator.encodeUncompressed())
    #expect(p256.count == CurvePoint<NistP256>.uncompressedByteCount)
    #expect(p384.count == CurvePoint<NistP384>.uncompressedByteCount)
    #expect(CurvePoint<NistP256>.decodeUncompressed(p256) == NistP256.generator)
    #expect(CurvePoint<NistP384>.decodeUncompressed(p384) == NistP384.generator)
    #expect(CurvePoint<NistP384>.decodeUncompressed(p256) == nil)
  }

  @Test
  internal func decodingRejectsAPointOffTheCurve() throws {
    var encoded = Array(try #require(NistP384.generator.encodeUncompressed()))
    encoded[encoded.count - 1] ^= 1
    #expect(CurvePoint<NistP384>.decodeUncompressed(Data(encoded)) == nil)
  }
}
