// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CardCore
import Foundation

/// Compact timestamp tokens: verified before their certificates are stripped.
extension TimestampClient {
  /// The compact exchange still asks the authority for its certificate.
  internal static func compactRequest(
    digest: Data,
    nonceBytes: Data
  ) -> Data {
    RfcTimestamp.request(digest: digest, nonceBytes: nonceBytes)
  }

  /// Verifies a full token before removing only its CertificateSet.
  internal static func verifiedCompactEncoding(
    _ token: Data,
    trustedCertificates: [Data]
  ) throws -> Data {
    let verified = try TimestampTokenVerifier.verify(
      token, trustedCertificates: trustedCertificates
    )
    guard
      let compact = CmsCertificates.removingCertificates(
        from: verified.token
      )
    else {
      throw RfcTimestamp.TokenFailure.malformed
    }
    return compact
  }
}
