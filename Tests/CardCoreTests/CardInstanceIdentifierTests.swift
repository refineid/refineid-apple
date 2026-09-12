// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CardCore
import Foundation
import Testing

@Suite
internal struct CardInstanceIdentifierTests {
  /// Synthetic bytes that are deliberately not an answer from a card.
  private static let syntheticLookupBytes = "0102030405060708090A0B0C0D0E0F10"

  /// SHA-256 of `syntheticLookupBytes`, computed with `shasum`.
  private static let syntheticLookupDigest =
    "5dfbabeedf318bf33c0927c43d7630f51b82f351740301354fa3d7fc51f0132e"

  @Test
  internal func primeLookupRefusesAnEmptyAnswerToReset() {
    #expect(PrimeLookupIdentifier(answerToReset: Data()) == nil)
  }

  @Test
  internal func primeLookupNamesItsHashAsInternalMaterial() throws {
    let lookup = try #require(
      PrimeLookupIdentifier(answerToReset: WireHex.data(Self.syntheticLookupBytes)))
    #expect(lookup.value == "refineid-prime-atr-sha256-" + Self.syntheticLookupDigest)
  }

  @Test
  internal func currentCardUsesThePrintedFinalNineCharacters() throws {
    let serial = try #require(TokenSerial(value: "SYNTHETICTEST00001"))
    let printed = try #require(PrintedCardSerial(tokenSerial: serial))
    let instance = try #require(CardInstanceIdentifier(tokenSerial: serial))
    #expect(printed.value == "TEST00001")
    #expect(instance.value == "refineid-card-test00001")
  }

  @Test
  internal func legacyCardUsesTheDocumentedMiddleWindow() throws {
    let serial = try #require(TokenSerial(value: "00000000001111111111"))
    let printed = try #require(PrintedCardSerial(tokenSerial: serial))
    let instance = try #require(CardInstanceIdentifier(tokenSerial: serial))
    #expect(printed.value == "111111111")
    #expect(instance.value == "refineid-card-111111111")
  }

  @Test
  internal func exactNineCharacterCurrentSerialIsAccepted() throws {
    let serial = try #require(TokenSerial(value: "TEST00001"))
    #expect(PrintedCardSerial(tokenSerial: serial)?.value == "TEST00001")
    #expect(CardInstanceIdentifier(tokenSerial: serial)?.value == "refineid-card-test00001")
  }

  @Test
  internal func tokenNamespaceBuildsAndRecognizesTheFullIdentifier() throws {
    let serial = try #require(TokenSerial(value: "TEST00001"))
    let instance = try #require(CardInstanceIdentifier(tokenSerial: serial))
    let tokenIdentifier = CardTokenNamespace.tokenIdentifier(for: instance)
    let neighboringDriver = "fi.refineid.ReFineID.token2:" + instance.value
    #expect(tokenIdentifier == "fi.refineid.ReFineID.token:refineid-card-test00001")
    #expect(CardTokenNamespace.owns(tokenIdentifier: tokenIdentifier))
    #expect(
      CardTokenNamespace.owns(
        tokenIdentifier: "fi.refineid.ReFineID.ctk:refineid-card-test00001"))
    #expect(!CardTokenNamespace.owns(tokenIdentifier: neighboringDriver))
  }

  @Test
  internal func displacedRemoteCardTokensAreRecognizedUnderEveryCardClass() {
    #expect(
      CardTokenNamespace.isDisplacedRemoteCardToken(
        tokenIdentifier: "fi.refineid.ReFineID.token:refineid-rapp-card-0011aabb"))
    #expect(
      CardTokenNamespace.isDisplacedRemoteCardToken(
        tokenIdentifier: "fi.refineid.ReFineID.ctk:refineid-rapp-card-0011aabb"))
    #expect(
      !CardTokenNamespace.isDisplacedRemoteCardToken(
        tokenIdentifier: "fi.refineid.ReFineID.token:refineid-card-test00001"))
    // Under its own driver class the remote card is where it belongs.
    #expect(
      !CardTokenNamespace.isDisplacedRemoteCardToken(
        tokenIdentifier: "fi.refineid.ReFineID.rapp-token:refineid-rapp-card-0011aabb"))
  }

  @Test
  internal func displacedConfigurationSelectionSparesSetupAndCards() {
    let displaced = DriverConfiguredCredentials.displacedRemoteCardConfigurationIDs(
      among: [
        "card-access-number",
        "refineid-card-test00001",
        "refineid-rapp-card-0011aabb",
        "refineid-rapp-card-ccddeeff",
      ])
    #expect(displaced == ["refineid-rapp-card-0011aabb", "refineid-rapp-card-ccddeeff"])
  }

  @Test
  internal func unknownShapesAreNotPublishedAsCardNames() throws {
    let short = try #require(TokenSerial(value: "SHORT"))
    let decimalWrongLength = try #require(TokenSerial(value: "0000000000"))
    let punctuatedTail = try #require(TokenSerial(value: "SYNTHETIC-TEST-01"))
    #expect(PrintedCardSerial(tokenSerial: short) == nil)
    #expect(CardInstanceIdentifier(tokenSerial: short) == nil)
    #expect(PrintedCardSerial(tokenSerial: decimalWrongLength) == nil)
    #expect(CardInstanceIdentifier(tokenSerial: decimalWrongLength) == nil)
    #expect(PrintedCardSerial(tokenSerial: punctuatedTail) == nil)
    #expect(CardInstanceIdentifier(tokenSerial: punctuatedTail) == nil)
  }
}
