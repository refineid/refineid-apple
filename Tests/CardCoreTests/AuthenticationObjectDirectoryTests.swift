// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation
import Testing

@testable import CardCore

/// EF.AOD parsing: each password object deconstructed to its reference
/// and length range, and a file that does not decode listing nothing.
@Suite
internal struct AuthenticationObjectDirectoryTests {
  /// Citizen password-object minimums (FINEID S4-1 v4.2 §8.1.5).
  private static let citizenPin1Minimum = 4
  private static let citizenPin2Minimum = 6
  private static let citizenPukMinimum = 8

  /// An organization card's PIN 1 object lists a maximum below its
  /// stored length.
  private static let organizationPin1Maximum = 8

  /// Zero padding after the objects.
  private static let paddingLength = 16

  /// A magnitude above one octet.
  private static let twoOctetLength = 300

  private static func range(_ minimum: Int, _ maximum: Int) throws -> PasswordLengthRange {
    try #require(PasswordLengthRange(minimum: minimum, maximum: maximum))
  }

  @Test
  internal func readsTheCitizenObjectsInFileOrder() throws {
    let file = AuthenticationObjectFixture.file([
      AuthenticationObjectFixture.citizen(
        reference: FineidValues.pin1Reference, minimum: Self.citizenPin1Minimum
      ).encoded,
      AuthenticationObjectFixture.citizen(
        reference: FineidValues.pin2Reference, minimum: Self.citizenPin2Minimum
      ).encoded,
      AuthenticationObjectFixture.citizen(
        reference: FineidValues.pukReference, minimum: Self.citizenPukMinimum
      ).encoded,
    ])
    let directory = try #require(AuthenticationObjectDirectory.parse(file))
    let stored = Int(AuthenticationObjectFixture.storedLength)
    #expect(
      directory.passwords == [
        .init(
          reference: FineidValues.pin1Reference,
          lengths: try Self.range(Self.citizenPin1Minimum, stored)),
        .init(
          reference: FineidValues.pin2Reference,
          lengths: try Self.range(Self.citizenPin2Minimum, stored)),
        .init(
          reference: FineidValues.pukReference,
          lengths: try Self.range(Self.citizenPukMinimum, stored)),
      ])
  }

  @Test
  internal func maximumLengthBoundsTheRangeWhenListed() throws {
    var object = AuthenticationObjectFixture.citizen(
      reference: FineidValues.organizationPin1Reference, minimum: Self.citizenPin1Minimum)
    object.maximum = Self.organizationPin1Maximum
    let directory = try #require(
      AuthenticationObjectDirectory.parse(AuthenticationObjectFixture.file([object.encoded])))
    #expect(
      directory.passwords.first?.lengths
        == (try Self.range(Self.citizenPin1Minimum, Self.organizationPin1Maximum)))
  }

  @Test
  internal func anOmittedReferenceIsTheDefault() throws {
    var object = AuthenticationObjectFixture.citizen(
      reference: FineidValues.pin1Reference, minimum: Self.citizenPin1Minimum)
    object.reference = nil
    let directory = try #require(
      AuthenticationObjectDirectory.parse(AuthenticationObjectFixture.file([object.encoded])))
    #expect(directory.passwords.first?.reference == Pkcs15Values.passwordReferenceDefault)
  }

  @Test
  internal func zeroPaddingEndsTheFile() throws {
    let object = AuthenticationObjectFixture.citizen(
      reference: FineidValues.pin1Reference, minimum: Self.citizenPin1Minimum)
    let file = AuthenticationObjectFixture.file([object.encoded], padding: Self.paddingLength)
    let directory = try #require(AuthenticationObjectDirectory.parse(file))
    #expect(directory.passwords.count == 1)
  }

  @Test
  internal func dataAfterThePaddingRejectsTheFile() {
    let object = AuthenticationObjectFixture.citizen(
      reference: FineidValues.pin1Reference, minimum: Self.citizenPin1Minimum)
    let file =
      AuthenticationObjectFixture.file([object.encoded], padding: Self.paddingLength)
      + object.encoded
    #expect(AuthenticationObjectDirectory.parse(file) == nil)
  }

  @Test
  internal func aTruncatedFileListsNothing() {
    let object = AuthenticationObjectFixture.citizen(
      reference: FineidValues.pin1Reference, minimum: Self.citizenPin1Minimum)
    #expect(AuthenticationObjectDirectory.parse(Data(object.encoded.dropLast())) == nil)
  }

  @Test
  internal func aPasswordObjectWithoutItsLengthsRejectsTheFile() {
    let flagsOnly = DerEncoder.tlv(
      DerValues.tagBitString, Data([DerValues.bitStringNoUnusedBits]))
    let file = AuthenticationObjectFixture.object(aroundAttributes: flagsOnly)
    #expect(AuthenticationObjectDirectory.parse(file) == nil)
  }

  @Test
  internal func objectsThatDoNotCountDigitsAreNotKept() throws {
    var bcd = AuthenticationObjectFixture.citizen(
      reference: FineidValues.pin1Reference, minimum: Self.citizenPin1Minimum)
    bcd.passwordType = AuthenticationObjectFixture.passwordTypeBcd
    var inverted = AuthenticationObjectFixture.citizen(
      reference: FineidValues.pin2Reference, minimum: Self.citizenPukMinimum)
    inverted.maximum = Self.citizenPin1Minimum
    var wide = AuthenticationObjectFixture.citizen(
      reference: FineidValues.pukReference, minimum: Self.citizenPukMinimum)
    wide.stored = Self.twoOctetLength
    let directory = try #require(
      AuthenticationObjectDirectory.parse(
        AuthenticationObjectFixture.file([bcd.encoded, inverted.encoded, wide.encoded])))
    #expect(directory.passwords.isEmpty)
  }

  @Test
  internal func objectsOfOtherKindsAreSkipped() throws {
    let otherKind = DerEncoder.tlv(Pkcs15Values.typeAttributesTag, Data())
    let pin = AuthenticationObjectFixture.citizen(
      reference: FineidValues.pin1Reference, minimum: Self.citizenPin1Minimum)
    let directory = try #require(
      AuthenticationObjectDirectory.parse(
        AuthenticationObjectFixture.file([otherKind, pin.encoded])))
    #expect(directory.passwords.map(\.reference) == [FineidValues.pin1Reference])
  }

  @Test
  internal func anEmptyFileListsNoObject() throws {
    let directory = try #require(AuthenticationObjectDirectory.parse(Data()))
    #expect(directory.passwords.isEmpty)
  }
}
