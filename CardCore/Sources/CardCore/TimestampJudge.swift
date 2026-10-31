// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// Judges one RFC 3161 token against the time-stamping anchors.
internal enum TimestampJudge {
  /// The state of `token`, whose TSTInfo imprint `imprintMatches`
  /// checks, under the hash the TSTInfo names, against what the token
  /// time-stamps (RFC 3161 section 2.4.2).
  ///
  /// A token that does not parse, or names a hash other than SHA-256,
  /// SHA-384 or SHA-512, is unsupported. The authority's path is first
  /// built under the time-stamping anchors as the only anchors, from
  /// the token's own and the document's certificates, at genTime; an
  /// authority revoked at or before genTime, or for a compromise, is
  /// not anchored. A token that does not anchor is verified under its
  /// own certificates and is claimed when that holds, invalid when not.
  internal static func state(
    of token: Data,
    imprintMatches: (CmsSignerVerification.Digest, Data) -> Bool,
    evidence: ValidationEvidence,
    anchors: [Data],
    now: Date
  ) -> TimestampState {
    guard
      let contents = try? RfcTimestamp.contents(in: token),
      let binding = try? RfcTimestamp.binding(in: contents.tstInfo),
      let digest = CmsSignerVerification.Digest(algorithmIdentifier: binding.algorithm)
    else {
      return .unsupported
    }
    guard
      binding.digest.count == digest.byteCount,
      imprintMatches(digest, binding.digest)
    else {
      return .invalid
    }
    if let anchored = try? TimestampTokenVerifier.verify(
      token,
      trustedCertificates: anchors,
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
        return .anchored(anchored.generatedAt)
      }
      return .claimed(anchored.generatedAt)
    }
    guard let claimed = try? TimestampTokenVerifier.verify(token) else {
      return .invalid
    }
    return .claimed(claimed.generatedAt)
  }
}
