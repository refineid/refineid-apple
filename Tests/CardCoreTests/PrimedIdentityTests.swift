// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CardCore
import Foundation
import Testing

@Suite
internal struct PrimedIdentityTests {
  /// Six digits standing in for a card access number in tests only.
  private static let sampleCan = "123456"

  /// A short DER-shaped byte string standing in for a certificate.
  private static let sampleCertificateHexDigits = "3082000102030405"

  /// A different DER-shaped byte string, standing in for the issuer.
  private static let sampleIssuerHexDigits = "308200010A0B0C0D"

  /// An unmistakably synthetic chip serial.
  private static let sampleSerialText = "SYNTHETIC-PRIME-SERIAL"

  /// The synthetic chip serial as its domain type.
  private static let sampleSerial: ChipSerial = {
    guard let serial = ChipSerial(value: sampleSerialText) else {
      fatalError("test serial must be valid")
    }
    return serial
  }()

  /// Coding key of the stored chip serial.
  private static let chipSerialKey = "chipSerial"

  /// Marker carried only by a prime whose live activation check passed.
  private static let activationCheck = PrimedIdentity.ActivationCheck.passed

  @Test
  internal func refusesACardAccessNumberThatIsNotSixDigits() {
    let certificate = WireHex.data(Self.sampleCertificateHexDigits)
    #expect(
      PrimedIdentity(
        can: "12345", certificate: certificate, issuer: nil, chipSerial: Self.sampleSerial,
        activationCheck: Self.activationCheck) == nil)
    #expect(
      PrimedIdentity(
        can: "12345a", certificate: certificate, issuer: nil, chipSerial: Self.sampleSerial,
        activationCheck: Self.activationCheck) == nil)
  }

  @Test
  internal func refusesAnEmptyCertificate() {
    #expect(
      PrimedIdentity(
        can: Self.sampleCan, certificate: Data(), issuer: nil, chipSerial: Self.sampleSerial,
        activationCheck: Self.activationCheck) == nil)
  }

  @Test
  internal func refusesToDecodeAMalformedStoredSerial() throws {
    let serial = try #require(ChipSerial(value: Self.sampleSerialText))
    let identity = try #require(
      PrimedIdentity(
        can: Self.sampleCan,
        certificate: WireHex.data(Self.sampleCertificateHexDigits),
        issuer: nil,
        chipSerial: serial,
        activationCheck: Self.activationCheck))
    let payload = try JSONEncoder().encode(identity)
    var object = try #require(
      JSONSerialization.jsonObject(with: payload) as? [String: Any])
    object[Self.chipSerialKey] = "not a serial"
    let tampered = try JSONSerialization.data(withJSONObject: object)
    #expect(throws: DecodingError.self) {
      try JSONDecoder().decode(PrimedIdentity.self, from: tampered)
    }
  }

  @Test
  internal func refusesToDecodeARecordWithoutASerial() throws {
    let identity = try #require(
      PrimedIdentity(
        can: Self.sampleCan,
        certificate: WireHex.data(Self.sampleCertificateHexDigits),
        issuer: nil,
        chipSerial: Self.sampleSerial,
        activationCheck: Self.activationCheck))
    let payload = try JSONEncoder().encode(identity)
    var object = try #require(
      JSONSerialization.jsonObject(with: payload) as? [String: Any])
    object[Self.chipSerialKey] = nil
    let stripped = try JSONSerialization.data(withJSONObject: object)
    #expect(throws: DecodingError.self) {
      try JSONDecoder().decode(PrimedIdentity.self, from: stripped)
    }
  }

  @Test
  internal func acceptsAPrimeWithoutIssuer() throws {
    let certificate = WireHex.data(Self.sampleCertificateHexDigits)
    let identity = try #require(
      PrimedIdentity(
        can: Self.sampleCan, certificate: certificate, issuer: nil, chipSerial: Self.sampleSerial,
        activationCheck: Self.activationCheck))
    #expect(identity.issuerDER == nil)
  }

  @Test
  internal func codingRoundTripPreservesEveryField() throws {
    let serial = try #require(ChipSerial(value: Self.sampleSerialText))
    let identity = try #require(
      PrimedIdentity(
        can: Self.sampleCan,
        certificate: WireHex.data(Self.sampleCertificateHexDigits),
        issuer: WireHex.data(Self.sampleIssuerHexDigits),
        chipSerial: serial,
        activationCheck: Self.activationCheck))
    let payload = try JSONEncoder().encode(identity)
    let decoded = try JSONDecoder().decode(PrimedIdentity.self, from: payload)
    #expect(decoded == identity)
    #expect(decoded.chipSerial == serial)
    #expect(decoded.activationCheck == .passed)
  }

  @Test
  internal func codingRoundTripPreservesAbsentOptionals() throws {
    let identity = try #require(
      PrimedIdentity(
        can: Self.sampleCan,
        certificate: WireHex.data(Self.sampleCertificateHexDigits),
        issuer: nil,
        chipSerial: Self.sampleSerial,
        activationCheck: Self.activationCheck))
    let payload = try JSONEncoder().encode(identity)
    let decoded = try JSONDecoder().decode(PrimedIdentity.self, from: payload)
    #expect(decoded == identity)
    #expect(decoded.issuerDER == nil)
    #expect(decoded.signatureCertDER == nil)
  }

  @Test
  internal func codingRoundTripPreservesSignatureCertificate() throws {
    let signatureCert = WireHex.data("308200010E0F1011")
    let serial = try #require(ChipSerial(value: Self.sampleSerialText))
    let identity = try #require(
      PrimedIdentity(
        can: Self.sampleCan,
        certificate: WireHex.data(Self.sampleCertificateHexDigits),
        issuer: WireHex.data(Self.sampleIssuerHexDigits),
        chipSerial: serial,
        activationCheck: Self.activationCheck,
        signatureCertificate: signatureCert))
    let payload = try JSONEncoder().encode(identity)
    let decoded = try JSONDecoder().decode(PrimedIdentity.self, from: payload)
    #expect(decoded == identity)
    #expect(decoded.signatureCertDER == signatureCert)
  }
}
