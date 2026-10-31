// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

extension CertificateRevocationList {
  /// What one authenticated CRL embedded as evidence says about one
  /// certificate, before any time window is applied.
  internal struct Evidence {
    /// The list's thisUpdate.
    internal let thisUpdate: Date

    /// The list's nextUpdate, when it states one.
    internal let nextUpdate: Date?

    /// The certificate's revoked entry, when the list names it.
    internal let revocation: RevokedEntry?
  }

  /// Authenticates `crl` as evidence for `certificate` under `issuer`,
  /// whose relationship the caller's certificate path already proved.
  ///
  /// The issuer must name the certificate's issuer and the list's
  /// issuer, may sign CRLs, and must have signed the exact TBSCertList.
  /// No time is consulted here; the caller judges the window.
  internal static func evidence(
    crl: Data,
    certificate: Data,
    issuerCertificate: Data
  ) throws -> Evidence {
    let encoded = try Self.derEncoded(from: crl)
    let target = try Self.certificateContext(from: certificate)
    let issuer = try Self.certificateContext(from: issuerCertificate)
    guard
      Self.issuer(of: target.certificate)
        == Self.subject(of: issuer.certificate)
    else {
      throw ValidationFailure.issuerMismatch
    }
    guard issuer.canSignCrl else {
      throw ValidationFailure.issuerUnauthorized
    }
    let parsed = try Self.parse(encoded, targetSerial: target.serialNumber)
    guard parsed.issuerName == issuer.subjectName else {
      throw ValidationFailure.issuerMismatch
    }
    let algorithm = try Self.signatureAlgorithm(from: parsed.signatureAlgorithm)
    guard
      Self.signatureIsValid(
        parsed.signature,
        over: parsed.signedData,
        with: issuer.certificate,
        algorithm: algorithm
      )
    else {
      throw ValidationFailure.signatureInvalid
    }
    return Evidence(
      thisUpdate: parsed.thisUpdate,
      nextUpdate: parsed.nextUpdate,
      revocation: parsed.targetRevocation
    )
  }
}
