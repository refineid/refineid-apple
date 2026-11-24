// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CardCore
import Foundation

/// Live signer-anchor discovery combining card-cached issuers (`EF.4336`) and
/// verified EU Trusted List certificate-issuing services (`TrustedListStore`).
extension ValidationMaterialCollector {
  /// Collects complete evidence using the live signing environment.
  ///
  /// Anchors the document signer on either the card-cached issuing certificate
  /// (`EF.4336`) or the EU Trusted Lists' qualified certificate-issuing
  /// services (`TrustedListStore`), so cards without on-card CA files
  /// (including Estonian eID) reach B-LTA.
  internal static func collect(
    signerCertificate: Data,
    timestampTokens: [TimestampTokenVerifier.VerifiedToken]
  ) async throws -> PdfValidationStore.Material {
    let trustedLists = try? await TrustedListStore.shared.signingAnchors().get()
    let now = Date()
    let anchors = Self.signerAnchors(
      for: signerCertificate,
      trustedListAnchors: trustedLists,
      at: now
    )
    return try await Self.collect(
      signerCertificate: signerCertificate,
      timestampTokens: timestampTokens,
      dependencies: .live,
      signerTrustCertificates: anchors,
      signerCandidates: Array(anchors)
    )
  }

  /// Resolves signer anchors from the card-cached issuing certificate alone.
  internal static func signerAnchors(for signerCertificate: Data) -> Set<Data> {
    Self.signerAnchors(for: signerCertificate, additionalAnchors: [], at: Date())
  }

  /// Resolves signer anchors combining card-cached `EF.4336` and any supplied
  /// candidate anchors that directly issued `signerCertificate` at `instant`.
  internal static func signerAnchors(
    for signerCertificate: Data,
    additionalAnchors: Set<Data>,
    at instant: Date
  ) -> Set<Data> {
    var anchors: Set<Data> = []
    if let cached = IssuerCertificate.der(matching: signerCertificate) {
      anchors.insert(cached)
    }
    for candidate in additionalAnchors
    where CertificateIssuer.isDirectlyIssued(signerCertificate, by: candidate, at: instant) {
      anchors.insert(candidate)
    }
    return anchors
  }

  /// Resolves signer anchors combining card-cached `EF.4336` and EU Trusted
  /// List `.certificateIssuing` certificates valid at `instant`.
  internal static func signerAnchors(
    for signerCertificate: Data,
    trustedListAnchors: TrustAnchors?,
    at instant: Date
  ) -> Set<Data> {
    let listed = Set(
      trustedListAnchors?.certificates(for: .certificateIssuing, at: instant) ?? []
    )
    return Self.signerAnchors(
      for: signerCertificate,
      additionalAnchors: listed,
      at: instant
    )
  }
}
