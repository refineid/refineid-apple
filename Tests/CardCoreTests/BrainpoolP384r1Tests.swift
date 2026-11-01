// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CardCore
import Foundation
import Testing

/// Checks the brainpoolP384r1 curve against its published parameters.
///
/// The domain parameters are stored as little-endian limb literals, so a
/// mistranscribed limb would be invisible on inspection. These tests are the
/// mechanical check: the RFC 5639 section 3.6 hex is transcribed once more
/// here, in the independent big-endian form, and the group laws are exercised
/// so that no wrong constant can pass quietly.
@Suite
internal struct BrainpoolP384r1Tests {
  /// RFC 5639 section 3.6: the base point `G`, SEC1 uncompressed.
  private static let generatorUncompressedHex = """
    04\
    1D1C64F068CF45FFA2A63A81B7C13F6B8847A3E77EF14FE3DB7FCAFE0CBD10E8\
    E826E03436D646AAEF87B2E247D4AF1E\
    8ABE1D7520F9C2A45CB1EB8E95CFD55262B70B29FEEC5864E19C054FF9912928\
    0E4646217791811142820341263C5315
    """

  /// RFC 5639 section 3.6: the subgroup order `n`, big-endian.
  private static let orderHex = """
    8CB91E82A3386D280F5D6F7E50E641DF152F7109ED5456B31F166E6CAC0425A7\
    CF3AB6AF6B7FC3103B883202E9046565
    """

  /// A fixed full-width scalar and its independently calculated public
  /// point from OpenSSL 3.6.3 on brainpoolP384r1.
  private static let opensslScalarHex = """
    4E457D06B0DE02D5B82379AD66269C1A6B5054051B55C61AD9BC8739A536214B\
    39342F18371577A7CC6C93E8E78D5FB8
    """

  private static let opensslPublicPointHex = """
    04\
    46E3D825C57916E104D899FC4C44ED2A4D0B8E2EBDF579632FC29FB5AAE89A\
    6CD2C023ED28ACB9D8814A9968305C05\
    702C48D4EC6B5AECBB079A34416A7DCE70E1FA062B3B66811FA7FE984E154DB2\
    2FD7556F25104F90C39232F64025A76131
    """

  /// Two arbitrary small scalars whose sum does not overflow 64 bits.
  private static let firstScalar: UInt64 = 1_234_567_890_123_456_789

  private static let secondScalar: UInt64 = 987_654_321_098_765_432

  /// The scalar two, for checking doubling against scalar multiplication.
  private static let scalarTwo = U384(2)

  @Test
  internal func generatorIsOnTheCurve() {
    #expect(BrainpoolP384r1.generator.isOnCurve())
    #expect(!BrainpoolP384r1.generator.isInfinity)
  }

  @Test
  internal func generatorMatchesPublishedParameters() {
    let expected = WireHex.data(Self.generatorUncompressedHex)
    #expect(BrainpoolP384r1.generator.encodeUncompressed() == expected)
  }

  @Test
  internal func orderMatchesPublishedParameters() {
    #expect(BrainpoolP384r1.order.bigEndianBytes() == WireHex.data(Self.orderHex))
    #expect(BrainpoolP384r1.cofactor == 1)
  }

  @Test
  internal func orderTimesGeneratorIsThePointAtInfinity() {
    let product = BrainpoolP384r1.multiplyGenerator(by: BrainpoolP384r1.order)
    #expect(product.isInfinity)
    #expect(product == CurvePoint<BrainpoolP384r1>.infinity)
  }

  @Test
  internal func zeroTimesGeneratorIsThePointAtInfinity() {
    #expect(BrainpoolP384r1.multiplyGenerator(by: U384.zero).isInfinity)
  }

  @Test
  internal func oneTimesGeneratorIsTheGenerator() {
    #expect(BrainpoolP384r1.multiplyGenerator(by: U384.one) == BrainpoolP384r1.generator)
  }

  @Test
  internal func fullWidthScalarMatchesOpenSSL() throws {
    let scalar = try #require(U384(bigEndianBytes: WireHex.data(Self.opensslScalarHex)))
    let point = BrainpoolP384r1.multiplyGenerator(by: scalar)
    #expect(point.encodeUncompressed() == WireHex.data(Self.opensslPublicPointHex))
  }

  @Test
  internal func scalarMultiplicationIsHomomorphic() {
    let first = BrainpoolP384r1.multiplyGenerator(by: U384(Self.firstScalar))
    let second = BrainpoolP384r1.multiplyGenerator(by: U384(Self.secondScalar))
    let sum = BrainpoolP384r1.multiplyGenerator(by: U384(Self.firstScalar + Self.secondScalar))
    #expect(first.adding(second) == sum)
    #expect(first.isOnCurve())
    #expect(sum.isOnCurve())
  }

  @Test
  internal func addingTheInverseGivesThePointAtInfinity() {
    let point = BrainpoolP384r1.multiplyGenerator(by: U384(Self.firstScalar))
    #expect(point.adding(point.negated()).isInfinity)
  }

  @Test
  internal func doublingAgreesWithScalarMultiplication() {
    let doubled = BrainpoolP384r1.generator.doubled()
    #expect(doubled == BrainpoolP384r1.multiplyGenerator(by: Self.scalarTwo))
    #expect(doubled.isOnCurve())
  }

  @Test
  internal func uncompressedEncodingRoundTrips() throws {
    let point = BrainpoolP384r1.multiplyGenerator(by: U384(Self.firstScalar))
    let encoded = try #require(point.encodeUncompressed())
    #expect(encoded.count == CurvePoint<BrainpoolP384r1>.uncompressedByteCount)
    #expect(CurvePoint<BrainpoolP384r1>.decodeUncompressed(encoded) == point)
  }

  @Test
  internal func infinityHasNoUncompressedEncoding() {
    #expect(CurvePoint<BrainpoolP384r1>.infinity.encodeUncompressed() == nil)
    #expect(CurvePoint<BrainpoolP384r1>.infinity.isOnCurve())
  }

  @Test
  internal func decodingRejectsAWrongLength() throws {
    let encoded = try #require(BrainpoolP384r1.generator.encodeUncompressed())
    #expect(CurvePoint<BrainpoolP384r1>.decodeUncompressed(encoded.dropLast()) == nil)
    #expect(CurvePoint<BrainpoolP384r1>.decodeUncompressed(encoded + Data([0x00])) == nil)
    #expect(CurvePoint<BrainpoolP384r1>.decodeUncompressed(Data()) == nil)
  }

  @Test
  internal func decodingRejectsANonUncompressedTag() throws {
    var encoded = Array(try #require(BrainpoolP384r1.generator.encodeUncompressed()))
    encoded[0] = 0x02
    #expect(CurvePoint<BrainpoolP384r1>.decodeUncompressed(Data(encoded)) == nil)
  }

  @Test
  internal func decodingRejectsAPointOffTheCurve() throws {
    var encoded = Array(try #require(BrainpoolP384r1.generator.encodeUncompressed()))
    let last = encoded.count - 1
    encoded[last] ^= 0x01
    #expect(CurvePoint<BrainpoolP384r1>.decodeUncompressed(Data(encoded)) == nil)
  }

  @Test
  internal func integerRejectsAnOversizeBigEndianValue() {
    #expect(U384(bigEndianBytes: Data(repeating: 0xFF, count: U384.byteCount + 1)) == nil)
    #expect(U384(bigEndianBytes: Data(repeating: 0xFF, count: U384.byteCount)) != nil)
  }

  @Test
  internal func integerBigEndianEncodingRoundTrips() throws {
    let value = U384(Self.firstScalar)
    let bytes = value.bigEndianBytes()
    #expect(bytes.count == U384.byteCount)
    #expect(try #require(U384(bigEndianBytes: bytes)) == value)
  }
}
