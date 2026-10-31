// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// The certificates, OCSP responses and CRLs available to one
/// verification: those the document carries and the issuing
/// certificates this device has read from cards.
///
/// The pool is evidence, never trust: a certificate in it can only
/// extend a path to an anchor, and an answer in it counts only once it
/// verifies under the issuer or an authorised responder.
internal struct ValidationEvidence {
  /// Candidate path certificates, the earliest added first.
  internal private(set) var certificates: [Data] = []

  /// Candidate OCSP responses.
  internal private(set) var ocspResponses: [Data] = []

  /// Candidate CRLs.
  internal private(set) var revocationLists: [Data] = []

  /// Adds certificates not yet held.
  internal mutating func add(certificates added: [Data]) {
    for certificate in added where !certificates.contains(certificate) {
      certificates.append(certificate)
    }
  }

  /// Adds OCSP responses and CRLs not yet held.
  internal mutating func add(ocspResponses responses: [Data], revocationLists lists: [Data]) {
    for response in responses where !ocspResponses.contains(response) {
      ocspResponses.append(response)
    }
    for list in lists where !revocationLists.contains(list) {
      revocationLists.append(list)
    }
  }

  /// Adds one store's material.
  internal mutating func add(_ material: PdfValidationStore.Material) {
    add(certificates: material.certificates)
    add(ocspResponses: material.ocspResponses, revocationLists: material.revocationLists)
  }

  /// Adds the certificates and RevocationInfoChoices of one CMS
  /// SignedData.
  internal mutating func add(cms: Data) {
    add(certificates: CmsCertificates.inside(cms))
    let information = CmsCertificates.revocationInformation(in: cms)
    add(
      ocspResponses: information.ocspResponses,
      revocationLists: information.revocationLists
    )
  }

  /// Adds the issuing certificates this device has read from cards,
  /// the direct issuer of `signer` first.
  internal mutating func addCardReadCertificates(issuing signer: Data) {
    if let issuer = IssuerCertificate.der(matching: signer) {
      add(certificates: [issuer])
    }
    add(certificates: TrustRootsCache.shared.allCertificates)
  }
}
