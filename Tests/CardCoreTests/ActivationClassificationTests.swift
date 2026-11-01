// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CardCore
import Foundation
import Testing

/// The activation decision: the reference numbering first, then a
/// citizen card's certificate validity start (FINEID S4-1 §4.6,
/// S4-2 v4.0 §4.2).
@Suite
internal struct ActivationClassificationTests {
  /// Issuer common name of the kind DVV gives its organizational CAs.
  private static let organizationalIssuer = "Organisational Certificates - Test"

  /// Subject common name of the synthetic authentication certificate.
  private static let holder = "Synthetic Holder"

  /// A synthetic authentication certificate valid from before the
  /// cutover, issued under `issuer`.
  private static func certificate(issuer: String) throws -> Data {
    let key = try CertificateRevocationListFixtures.makeKey(for: .ecdsaSha256)
    return try CertificateRevocationListFixtures.certificate(
      description: .init(
        allowsCrlSigning: false,
        includesKeyUsage: true,
        malformedKeyUsage: false,
        commonName: Self.holder,
        isCertificateAuthority: false,
        issuerName: CertificateRevocationListFixtures.name(issuer),
        serial: CertificateRevocationListFixtures.targetSerial
      ),
      publicKey: key,
      signer: key,
      kind: .ecdsaSha256
    )
  }

  @Test
  internal func organizationNumberingIsTheActivationCodeSchemeWhateverTheCertificate() throws {
    let certificate = try Self.certificate(issuer: Self.holder)
    let undated = Data(Self.holder.utf8)
    for supplied in [certificate, undated, nil] {
      let decided = ActivationClassification.decide(
        numbering: .organization,
        authenticationCertificateDER: supplied
      )
      #expect(decided == .organization)
      #expect(decided?.scheme == .activationCodeIsPuk)
    }
  }

  @Test
  internal func citizenNumberingTakesTheCertificateDate() throws {
    let certificate = try Self.certificate(issuer: Self.holder)
    #expect(
      ActivationClassification.decide(
        numbering: .citizen,
        authenticationCertificateDER: certificate
      ) == .citizen(.activationCodeIsPuk)
    )
  }

  @Test
  internal func theIssuerNameDecidesNothing() throws {
    let certificate = try Self.certificate(issuer: Self.organizationalIssuer)
    #expect(
      ActivationClassification.decide(
        numbering: .citizen,
        authenticationCertificateDER: certificate
      ) == .citizen(.activationCodeIsPuk)
    )
  }

  @Test
  internal func anUnreadableCitizenCertificateGivesNoDecision() {
    #expect(
      ActivationClassification.decide(
        numbering: .citizen,
        authenticationCertificateDER: Data(Self.holder.utf8)
      ) == nil
    )
    #expect(
      ActivationClassification.decide(
        numbering: .citizen,
        authenticationCertificateDER: nil
      ) == nil
    )
  }

  /// An organization card is classified from the numbering alone; no
  /// certificate is read.
  @Test
  internal func anOrganizationCardIsClassifiedWithoutACertificateRead() {
    let channel = ScriptedChannel([
      ("0020001100", "6A88"),
      ("0020000300", "63C0"),
    ])
    let operations = CardOperations(channel: channel)
    #expect(operations.activationClassification() == .organization)
    #expect(channel.isExhausted)
  }
}
