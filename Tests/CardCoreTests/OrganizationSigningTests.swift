// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CardCore
import Foundation
import Testing

/// The organization card's sign chain at the operations level: MSE:SET
/// DST exactly as on the citizen card, then the host digest inline in
/// PSO:CDS's data field - no PSO:HASH exists for an external hash there
/// (Idemia organizational cards specification §6.6.2.3).
@Suite
internal struct OrganizationSigningTests {
  @Test
  internal func qualifiedChainCarriesTheDigestInsidePsoCds() throws {
    let digest = String(repeating: "AB", count: 32)
    let firstSignaturePart = String(repeating: "11", count: 256)
    let secondSignaturePart = String(repeating: "22", count: 128)
    // PIN2 verification resolves the numbering; the sign chain then
    // reuses it without a probe of its own. The qualified key is
    // local to DF.ESIGN, so its reference carries the local bit
    // (IAS-ECC v1.0.1 §4.4): 84 01 82. RSA-3072 answers 384 bytes
    // through the usual GET RESPONSE continuation.
    let channel = ScriptedChannel([
      ("0020001100", "6A88"),
      ("0020000300", "63C5"),
      ("0020000406363534333231", "9000"),
      ("002241B606800142840182", "9000"),
      ("002A9E9A20" + digest + "00", firstSignaturePart + "6180"),
      ("00C0000080", secondSignaturePart + "9000"),
    ])
    let operations = CardOperations(channel: channel)
    guard let pin = Pin2(digits: "654321") else {
      Issue.record("valid PIN failed to construct")
      return
    }
    try operations.verifyPin2(pin.consumeForSingleTransmission())

    let raw = try operations.computeQualifiedSignature(
      overDigest: WireHex.data(digest),
      algorithm: SigningAlgorithm(hash: .sha256, scheme: .rsaPkcs1),
      expectedSignatureLength: nil
    )

    #expect(raw == WireHex.data(firstSignaturePart + secondSignaturePart))
    #expect(raw.count == 384)
    #expect(channel.isExhausted)
  }

  @Test
  internal func citizenChainIsUnchangedWhenResolutionSaysCitizen() throws {
    let digest = String(repeating: "AB", count: 32)
    let signature = String(repeating: "11", count: 256)
    // A session resolved as citizen keeps the historical PSO:HASH +
    // empty PSO:CDS sequence byte for byte.
    let channel = ScriptedChannel([
      ("0020001100", "63C5"),
      ("002000110C313233343536000000000000", "9000"),
      ("002241B606800142840101", "9000"),
      ("002A90A0229020" + digest, "9000"),
      ("002A9E9A00", signature + "9000"),
    ])
    let operations = CardOperations(channel: channel)
    guard let pin = Pin1(digits: "123456") else {
      Issue.record("valid PIN failed to construct")
      return
    }
    try operations.verifyPin1(pin.consumeForSingleTransmission())

    let raw = try operations.computeAuthenticationSignature(
      overDigest: WireHex.data(digest),
      algorithm: SigningAlgorithm(hash: .sha256, scheme: .rsaPkcs1),
      expectedSignatureLength: nil
    )

    #expect(raw == WireHex.data(signature))
    #expect(channel.isExhausted)
  }

  @Test
  internal func aPin2ChannelSignsInEsignWithNoProbeAndNoVerify() throws {
    // PACE with PIN 2 counts as PIN 2 verified and resolves the
    // organization numbering, so the chain is DF.ESIGN by name from the
    // main file, MSE:SET under the local qualified key reference 82, and
    // one PSO:CDS with the digest inline -- no VERIFY of either form,
    // which the card refuses inside such a channel.
    let digest = String(repeating: "CD", count: 32)
    let signature = String(repeating: "33", count: 256)
    let channel = ScriptedChannel([
      ("00A4000C023F00", "9000"),
      ("00A4040C06452E5349474E", "9000"),
      ("002241B606800142840182", "9000"),
      ("002A9E9A20" + digest + "00", signature + "9000"),
    ])
    let operations = CardOperations(channel: channel, openedWith: .pin2)
    try operations.selectEsignDirectory()
    let raw = try operations.computeQualifiedSignature(
      overDigest: WireHex.data(digest),
      algorithm: SigningAlgorithm(hash: .sha256, scheme: .rsaPkcs1),
      expectedSignatureLength: nil
    )
    #expect(raw == WireHex.data(signature))
    #expect(channel.isExhausted)
    #expect(operations.channelPin == .pin2)
  }

  @Test
  internal func aPin1ChannelSignsWithTheDigestInlineAndNoVerify() throws {
    let digest = String(repeating: "AB", count: 32)
    let signature = String(repeating: "44", count: 256)
    let channel = ScriptedChannel([
      ("002241B606800142840101", "9000"),
      ("002A9E9A20" + digest + "00", signature + "9000"),
    ])
    let operations = CardOperations(channel: channel, openedWith: .pin1)
    let raw = try operations.computeAuthenticationSignature(
      overDigest: WireHex.data(digest),
      algorithm: SigningAlgorithm(hash: .sha256, scheme: .rsaPkcs1),
      expectedSignatureLength: nil
    )
    #expect(raw == WireHex.data(signature))
    #expect(channel.isExhausted)
  }
}
