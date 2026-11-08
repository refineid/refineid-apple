// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation
import Security

/// Judges one RFC 3161 token against the time-stamping anchors.
internal enum TimestampJudge {
  /// One judged token: its state, and for an anchored one until when
  /// it keeps proving its time.
  internal struct Judged {
    internal let state: TimestampState

    /// The earliest of every notAfter on the authority's verified
    /// chain and the end the cryptographic suitability table gives the
    /// token's signature algorithm and key; nil unless anchored.
    internal let validUntil: Date?
  }

  /// The state of `token`; see `judged(_:imprintMatches:evidence:anchors:now:)`.
  internal static func state(
    of token: Data,
    imprintMatches: (CmsSignerVerification.Digest, Data) -> Bool,
    evidence: ValidationEvidence,
    anchors: TrustAnchors,
    now: Date
  ) -> TimestampState {
    Self.judged(
      token, imprintMatches: imprintMatches, evidence: evidence, anchors: anchors, now: now
    ).state
  }

  /// Until when an anchored token keeps proving its time.
  ///
  /// The earliest notAfter on its verified chain, anchor included, and
  /// the end of its algorithm's suitability. A key the table does not
  /// accept ends it before any time.
  internal static func validUntil(of verified: TimestampTokenVerifier.VerifiedToken) -> Date {
    let ends = verified.verifiedCertificateChain.compactMap { certificate in
      CertificateValidity.window(inDer: certificate)?.notAfter
    }
    let suitability: CryptographicSuitability.Verdict
    if let digest = try? TimestampCmsVerifier.layout(in: verified.token).digest,
      let certificate = SecCertificateCreateWithData(nil, verified.signerCertificate as CFData),
      let publicKey = SecCertificateCopyKey(certificate),
      let key = CryptographicSuitability.Key(publicKey)
    {
      suitability = CryptographicSuitability.verdict(for: key, digest: digest)
    } else {
      suitability = .unacceptable
    }
    return Self.validUntil(chainEnds: ends, suitability: suitability)
  }

  /// The earliest of `chainEnds` and the end `suitability` gives; before
  /// any time when the algorithm is not acceptable or no end is known.
  internal static func validUntil(
    chainEnds: [Date],
    suitability: CryptographicSuitability.Verdict
  ) -> Date {
    var ends = chainEnds
    switch suitability {
    case .unlimited:
      break

    case .until(let end):
      ends.append(end)

    case .unacceptable:
      return Date.distantPast
    }
    return ends.min() ?? Date.distantPast
  }

  /// The state of `token`, whose TSTInfo imprint `imprintMatches`
  /// checks, under the hash the TSTInfo names, against what the token
  /// time-stamps (RFC 3161 section 2.4.2).
  ///
  /// A token that does not parse, or names a hash other than SHA-256,
  /// SHA-384 or SHA-512, is unsupported. The authority's path is first
  /// built under the time-stamping anchors granted at genTime as the
  /// only anchors, from the token's own and the document's
  /// certificates, at genTime; an authority revoked at or before
  /// genTime, or for a compromise, is not anchored. A token that does
  /// not anchor is verified under its own certificates and is claimed
  /// when that holds, invalid when not.
  internal static func judged(
    _ token: Data,
    imprintMatches: (CmsSignerVerification.Digest, Data) -> Bool,
    evidence: ValidationEvidence,
    anchors: TrustAnchors,
    now: Date
  ) -> Judged {
    guard
      let contents = try? RfcTimestamp.contents(in: token),
      let binding = try? RfcTimestamp.binding(in: contents.tstInfo),
      let digest = CmsSignerVerification.Digest(algorithmIdentifier: binding.algorithm)
    else {
      return Judged(state: .unsupported, validUntil: nil)
    }
    guard
      binding.digest.count == digest.byteCount,
      imprintMatches(digest, binding.digest)
    else {
      return Judged(state: .invalid, validUntil: nil)
    }
    if let anchored = try? TimestampTokenVerifier.verify(
      token,
      trustedCertificates: anchors.certificates(for: .timeStamping, at: contents.generatedAt),
      additionalCertificates: evidence.certificates
    ) {
      var tokenEvidence = evidence
      tokenEvidence.add(cms: token)
      let revocation = RevocationJudge.status(
        ofPath: anchored.verifiedCertificateChain,
        evidence: tokenEvidence,
        at: anchored.generatedAt,
        now: now
      )
      if !revocation.invalidates(proofOfExistence: anchored.generatedAt) {
        return Judged(
          state: .anchored(anchored.generatedAt), validUntil: Self.validUntil(of: anchored))
      }
      return Judged(state: .claimed(anchored.generatedAt), validUntil: nil)
    }
    guard let claimed = try? TimestampTokenVerifier.verify(token) else {
      return Judged(state: .invalid, validUntil: nil)
    }
    return Judged(state: .claimed(claimed.generatedAt), validUntil: nil)
  }
}
