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

  /// An unmistakably synthetic PKCS#15 token serial.
  private static let sampleSerial = "SYNTHETIC-PRIME-SERIAL"

  /// Marker carried only by a prime whose live activation check passed.
  private static let activationCheck = PrimedIdentity.ActivationCheck.passed

  @Test
  internal func refusesACardAccessNumberThatIsNotSixDigits() {
    let certificate = WireHex.data(Self.sampleCertificateHexDigits)
    #expect(
      PrimedIdentity(
        can: "12345", certificate: certificate, issuer: nil, tokenSerial: nil,
        activationCheck: Self.activationCheck) == nil)
    #expect(
      PrimedIdentity(
        can: "12345a", certificate: certificate, issuer: nil, tokenSerial: nil,
        activationCheck: Self.activationCheck) == nil)
  }

  @Test
  internal func refusesAnEmptyCertificate() {
    #expect(
      PrimedIdentity(
        can: Self.sampleCan, certificate: Data(), issuer: nil, tokenSerial: nil,
        activationCheck: Self.activationCheck) == nil)
  }

  @Test
  internal func refusesAnImplausibleSerial() {
    let certificate = WireHex.data(Self.sampleCertificateHexDigits)
    #expect(
      PrimedIdentity(
        can: Self.sampleCan, certificate: certificate, issuer: nil, tokenSerial: "",
        activationCheck: Self.activationCheck) == nil)
  }

  @Test
  internal func acceptsAPrimeWithoutIssuerOrSerial() throws {
    let certificate = WireHex.data(Self.sampleCertificateHexDigits)
    let identity = try #require(
      PrimedIdentity(
        can: Self.sampleCan, certificate: certificate, issuer: nil, tokenSerial: nil,
        activationCheck: Self.activationCheck))
    #expect(identity.issuerDER == nil)
    #expect(identity.tokenSerial == nil)
  }

  @Test
  internal func codingRoundTripPreservesEveryField() throws {
    let identity = try #require(
      PrimedIdentity(
        can: Self.sampleCan,
        certificate: WireHex.data(Self.sampleCertificateHexDigits),
        issuer: WireHex.data(Self.sampleIssuerHexDigits),
        tokenSerial: Self.sampleSerial,
        activationCheck: Self.activationCheck))
    let payload = try JSONEncoder().encode(identity)
    let decoded = try JSONDecoder().decode(PrimedIdentity.self, from: payload)
    #expect(decoded == identity)
    #expect(decoded.activationCheck == .passed)
  }

  @Test
  internal func codingRoundTripPreservesAbsentOptionals() throws {
    let identity = try #require(
      PrimedIdentity(
        can: Self.sampleCan,
        certificate: WireHex.data(Self.sampleCertificateHexDigits),
        issuer: nil,
        tokenSerial: nil,
        activationCheck: Self.activationCheck))
    let payload = try JSONEncoder().encode(identity)
    let decoded = try JSONDecoder().decode(PrimedIdentity.self, from: payload)
    #expect(decoded == identity)
    #expect(decoded.issuerDER == nil)
    #expect(decoded.tokenSerial == nil)
    #expect(decoded.signatureCertDER == nil)
  }

  @Test
  internal func codingRoundTripPreservesSignatureCertificate() throws {
    let signatureCert = WireHex.data("308200010E0F1011")
    let identity = try #require(
      PrimedIdentity(
        can: Self.sampleCan,
        certificate: WireHex.data(Self.sampleCertificateHexDigits),
        issuer: WireHex.data(Self.sampleIssuerHexDigits),
        tokenSerial: Self.sampleSerial,
        activationCheck: Self.activationCheck,
        signatureCertificate: signatureCert))
    let payload = try JSONEncoder().encode(identity)
    let decoded = try JSONDecoder().decode(PrimedIdentity.self, from: payload)
    #expect(decoded == identity)
    #expect(decoded.signatureCertDER == signatureCert)
  }
}
