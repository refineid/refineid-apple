// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CardCore
import Foundation
import Testing

/// Reading the one name a person is shown, out of a Name that repeats
/// the same identity in several attributes.
@Suite
internal struct DistinguishedNameTests {
  /// The object identifiers this fixture needs.
  private static let commonNameOid: [UInt8] = [0x06, 0x03, 0x55, 0x04, 0x03]
  private static let surnameOid: [UInt8] = [0x06, 0x03, 0x55, 0x04, 0x04]
  private static let countryOid: [UInt8] = [0x06, 0x03, 0x55, 0x04, 0x06]

  /// A Name in the shape a citizen certificate uses: country, the
  /// repeated attributes, then the common name.
  private static func citizenName(
    common: String,
    commonTag: UInt8 = 0x0C
  ) -> Data {
    let body =
      Self.attribute(oid: Self.countryOid, value: Self.element(0x13, Array("FI".utf8)))
      + Self.attribute(oid: Self.surnameOid, value: Self.element(0x0C, Array("SURNAME".utf8)))
      + Self.attribute(
        oid: Self.commonNameOid,
        value: Self.element(commonTag, Array(common.utf8))
      )
    return Data(Self.element(0x30, body))
  }

  /// A DER type-length-value.
  private static func element(_ tag: UInt8, _ content: [UInt8]) -> [UInt8] {
    var out: [UInt8] = [tag]
    if content.count < 0x80 {
      out.append(UInt8(content.count))
    } else {
      out.append(0x81)
      out.append(UInt8(content.count))
    }
    out.append(contentsOf: content)
    return out
  }

  /// A subject stating a given name and a surname of their own, the
  /// way a citizen certificate does.
  private static func personalName(given: String, family: String) -> Data {
    let body =
      Self.attribute(
        oid: [0x06, 0x03, 0x55, 0x04, 0x2A],
        value: Self.element(0x0C, Array(given.utf8))
      )
      + Self.attribute(
        oid: Self.surnameOid, value: Self.element(0x0C, Array(family.utf8))
      )
    return Data(Self.element(0x30, body))
  }

  /// One relative name holding one attribute.
  private static func attribute(oid: [UInt8], value: [UInt8]) -> [UInt8] {
    Self.element(0x31, Self.element(0x30, oid + value))
  }

  @Test
  internal func theCommonNameIsFoundAmongTheOtherAttributes() {
    let name = Self.citizenName(common: "SURNAME FORENAME 000000A")

    #expect(
      DistinguishedName.commonName(inName: name) == "SURNAME FORENAME 000000A"
    )
  }

  @Test
  internal func aPrintableStringCommonNameIsRead() {
    let name = Self.citizenName(common: "PLAIN NAME", commonTag: 0x13)

    #expect(DistinguishedName.commonName(inName: name) == "PLAIN NAME")
  }

  @Test
  internal func nonAsciiSurvivesAsWritten() {
    // A Finnish or French holder's name is not ASCII, and a common
    // name that arrives mangled is worse than one that is absent.
    let name = Self.citizenName(common: "MÄKELÄ ÉLODIE 000000A")

    #expect(
      DistinguishedName.commonName(inName: name) == "MÄKELÄ ÉLODIE 000000A"
    )
  }

  @Test
  internal func theNameIsRecasedForReading() {
    // Segments begin after a space or a hyphen, and nowhere else.
    // Diacritics survive: a Finnish name is the ordinary case here.
    let name = Self.personalName(given: "MARIA-ELISABETH", family: "SÄÄTILÄ")

    #expect(
      DistinguishedName.personalName(inName: name) == "Maria-Elisabeth Säätilä"
    )
    #expect(
      DistinguishedName.givenName(inName: name) == "Maria-Elisabeth"
    )
    #expect(DistinguishedName.surname(inName: name) == "Säätilä")
  }

  @Test
  internal func recasingLeavesTheNamesItCannotKnow() {
    // Known limits, kept deliberately: guessing at these would
    // misspell as many names as it fixed.
    let scottish = Self.personalName(given: "IAN", family: "MCCABE")
    let dutch = Self.personalName(given: "JAN", family: "VAN DER BERG")

    #expect(DistinguishedName.personalName(inName: scottish) == "Ian Mccabe")
    #expect(
      DistinguishedName.personalName(inName: dutch) == "Jan Van Der Berg"
    )
  }

  @Test
  internal func aLetterAfterAnApostropheStartsItsOwnSegment() {
    // Every surname carrying an apostrophe capitalises what follows
    // it, whichever apostrophe the certificate used.
    let irish = Self.personalName(given: "SEAN", family: "O'BRIEN")
    let italian = Self.personalName(given: "GINO", family: "D\u{2019}ANGELO")

    #expect(DistinguishedName.personalName(inName: irish) == "Sean O'Brien")
    #expect(
      DistinguishedName.personalName(inName: italian) == "Gino D\u{2019}Angelo"
    )
  }

  @Test
  internal func aNameWithoutACommonNameAnswersNothing() {
    let body =
      Self.attribute(oid: Self.countryOid, value: Self.element(0x13, Array("FI".utf8)))
      + Self.attribute(oid: Self.surnameOid, value: Self.element(0x0C, Array("SURNAME".utf8)))
    let name = Data(Self.element(0x30, body))

    #expect(DistinguishedName.commonName(inName: name) == nil)
  }

  @Test
  internal func aCommonNameInAnUnreadableStringIsRefused() {
    // BMPString is a wide encoding this does not decode. Guessing at
    // one produces a name that looks right and is not.
    let name = Self.citizenName(common: "WIDE", commonTag: 0x1E)

    #expect(DistinguishedName.commonName(inName: name) == nil)
  }

  @Test
  internal func theHolderLineShowsTheNameWithoutTheIdentifier() throws {
    let givenOid: [UInt8] = [0x06, 0x03, 0x55, 0x04, 0x2A]
    let serialOid: [UInt8] = [0x06, 0x03, 0x55, 0x04, 0x05]
    let body =
      Self.attribute(
        oid: givenOid, value: Self.element(0x0C, Array("MARIA-ELISABETH".utf8))
      )
      + Self.attribute(
        oid: Self.surnameOid, value: Self.element(0x0C, Array("SÄÄTILÄ".utf8))
      )
      + Self.attribute(
        oid: serialOid, value: Self.element(0x13, Array("000000A".utf8))
      )
    let name = Data(Self.element(0x30, body))

    #expect(
      DistinguishedName.holderLine(inName: name) == "SÄÄTILÄ MARIA-ELISABETH"
    )

    let citizen = Self.citizenName(common: "KOISTINEN PETRI 12345678A")
    #expect(
      DistinguishedName.holderLine(inName: citizen) == "KOISTINEN PETRI"
    )

    let compound = Self.citizenName(common: "MÖTTÖNEN MATTI-ÄNKYRÄ 87654321B")
    #expect(
      DistinguishedName.holderLine(inName: compound) == "MÖTTÖNEN MATTI-ÄNKYRÄ"
    )

    #expect(
      DistinguishedName.identifier(inName: citizen) == nil
    )
    let certWithCommon = try MockCardCertificate.makeCertificate(
      commonName: "KOISTINEN PETRI 12345678A"
    )
    #expect(
      DistinguishedName.identifier(fromCertificate: certWithCommon) == "12345678A"
    )
  }

  @Test
  internal func somethingThatIsNotANameAnswersNothing() {
    #expect(DistinguishedName.commonName(inName: Data()) == nil)
    #expect(DistinguishedName.commonName(inName: Data([0x02, 0x01, 0x05])) == nil)
  }
}
