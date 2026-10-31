// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation
import Security

/// Builds and validates one certificate path to a trust anchor
/// (RFC 5280 section 6; EN 319 102-1 clause 5.2.6).
///
/// The platform's basic X.509 evaluation runs offline under the
/// anchors as its exclusive anchor set: name chaining, signatures,
/// validity at the validation time, basic constraints, key usage, path
/// length, name constraints and critical extensions are checked on
/// every certificate below the anchor. Candidate certificates only
/// supply intermediates; none of them becomes an anchor.
internal enum CertificatePath {
  /// The validated path from `certificate` to an anchor, the
  /// certificate first and the anchor last, or empty when no path
  /// reaches an anchor at `validationTime`.
  ///
  /// A certificate byte-identical to an anchor is a path of one; the
  /// path ends at an anchor's exact certificate.
  internal static func anchored(
    _ certificate: Data,
    candidates: [Data],
    anchors: [Data],
    at validationTime: Date
  ) -> [Data] {
    guard !anchors.isEmpty else { return [] }
    if anchors.contains(certificate) {
      return [certificate]
    }
    guard let leaf = SecCertificateCreateWithData(nil, certificate as CFData) else { return [] }
    // A candidate the platform does not parse is left out; it cannot
    // extend a path, and the others still can.
    let intermediates = candidates.filter { $0 != certificate }.compactMap { candidate in
      SecCertificateCreateWithData(nil, candidate as CFData)
    }
    let parsed = [leaf] + intermediates
    let anchorCertificates = anchors.compactMap { anchor in
      SecCertificateCreateWithData(nil, anchor as CFData)
    }
    guard !anchorCertificates.isEmpty else { return [] }
    var created: SecTrust?
    guard
      SecTrustCreateWithCertificates(
        parsed as CFArray, SecPolicyCreateBasicX509(), &created
      ) == errSecSuccess,
      let trust = created,
      SecTrustSetAnchorCertificates(trust, anchorCertificates as CFArray) == errSecSuccess,
      SecTrustSetAnchorCertificatesOnly(trust, true) == errSecSuccess,
      SecTrustSetNetworkFetchAllowed(trust, false) == errSecSuccess,
      SecTrustSetVerifyDate(trust, validationTime as CFDate) == errSecSuccess
    else {
      return []
    }
    var error: CFError?
    guard
      SecTrustEvaluateWithError(trust, &error),
      let chain = SecTrustCopyCertificateChain(trust) as? [SecCertificate]
    else {
      return []
    }
    let encoded = chain.map { SecCertificateCopyData($0) as Data }
    guard
      encoded.first == certificate,
      let terminal = encoded.last,
      anchors.contains(terminal)
    else {
      return []
    }
    return encoded
  }

  /// The candidate that directly issued `certificate` at
  /// `validationTime`, for reporting when no anchored path exists.
  internal static func directIssuer(
    of certificate: Data,
    candidates: [Data],
    at validationTime: Date
  ) -> Data? {
    candidates.first { candidate in
      candidate != certificate
        && CertificateIssuer.isDirectlyIssued(certificate, by: candidate, at: validationTime)
    }
  }

  /// Whether a document signer may sign: no CA, a Key Usage without
  /// certificate or CRL signing, and no critical extension this
  /// verifier does not process (RFC 5280 sections 4.2.1.3, 4.2.1.9).
  internal static func isFitToSign(_ certificate: Data) -> Bool {
    guard let parsed = CertificateIssuer.parsed(certificate) else { return false }
    return CertificateIssuer.isPermittedEndEntity(parsed)
  }
}
