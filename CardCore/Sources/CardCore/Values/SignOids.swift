// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

/// The object identifiers document signing speaks, in dotted notation.
///
/// Encoded arithmetically by `DerEncoder.objectIdentifier`; the dotted
/// form is the named constant, so no encoded OID byte exists outside
/// the encoder.
internal enum SignOids {
  /// CMS SignedData version 1: the version PAdES writes, since it
  /// carries no attribute certificates and no OCSP in the CMS itself
  /// (RFC 5652 §5.1).
  internal static let cmsVersion: Int = 1

  /// SignerInfo version 1: the issuer-and-serial form (RFC 5652 §5.3).
  internal static let signerInfoVersion: Int = 1

  /// TimeStampReq version 1, the only one defined (RFC 3161 §2.4.1).
  internal static let timestampRequestVersion: Int = 1

  /// TSTInfo version 1, the only one defined (RFC 3161 §2.4.2).
  internal static let tstInfoVersion: Int = 1

  /// PKIStatus values that carry a usable token: granted, and granted
  /// with modifications (RFC 3161 §2.4.2).
  internal static let grantedStatuses: Set<Int> = [0, 1]

  /// id-data (RFC 5652).
  internal static let data = "1.2.840.113549.1.7.1"

  /// id-signedData (RFC 5652).
  internal static let signedData = "1.2.840.113549.1.7.2"

  /// id-contentType signed attribute (RFC 5652).
  internal static let contentType = "1.2.840.113549.1.9.3"

  /// id-messageDigest signed attribute (RFC 5652).
  internal static let messageDigest = "1.2.840.113549.1.9.4"

  /// id-aa-signingCertificateV2 (RFC 5035).
  internal static let signingCertificateV2 = "1.2.840.113549.1.9.16.2.47"

  /// id-aa-signingCertificate, the SHA-1 predecessor to version 2
  /// (RFC 2634).
  internal static let signingCertificate = "1.2.840.113549.1.9.16.2.12"

  /// id-aa-signatureTimeStampToken (RFC 3161 appendix A).
  internal static let signatureTimestampToken = "1.2.840.113549.1.9.16.2.14"

  /// id-ct-TSTInfo (RFC 3161).
  internal static let tstInfo = "1.2.840.113549.1.9.16.1.4"

  /// id-at-commonName: the one name in a subject meant for a person
  /// to read (RFC 5280 appendix A).
  internal static let commonName = "2.5.4.3"

  /// id-at-surname (RFC 5280 appendix A).
  internal static let surname = "2.5.4.4"

  /// id-at-serialNumber, which on a citizen certificate carries the
  /// holder's electronic transaction identifier.
  internal static let serialNumber = "2.5.4.5"

  /// id-at-givenName.
  internal static let givenName = "2.5.4.42"

  /// SHA-384 (RFC 5754); parameters absent, never NULL.
  internal static let sha384 = "2.16.840.1.101.3.4.2.2"

  /// SHA-256 (RFC 5754).
  internal static let sha256 = "2.16.840.1.101.3.4.2.1"

  /// SHA-512 (RFC 5754).
  internal static let sha512 = "2.16.840.1.101.3.4.2.3"

  /// ecdsa-with-SHA384 (RFC 5758); no parameters.
  internal static let ecdsaWithSha384 = "1.2.840.10045.4.3.3"

  /// ecdsa-with-SHA256 (RFC 5758); no parameters.
  internal static let ecdsaWithSha256 = "1.2.840.10045.4.3.2"

  /// ecdsa-with-SHA512 (RFC 5758); no parameters.
  internal static let ecdsaWithSha512 = "1.2.840.10045.4.3.4"

  /// sha256WithRSAEncryption (RFC 8017 appendix A.2.4).
  internal static let sha256WithRsa = "1.2.840.113549.1.1.11"

  /// sha384WithRSAEncryption (RFC 8017 appendix A.2.4).
  internal static let sha384WithRsa = "1.2.840.113549.1.1.12"

  /// sha512WithRSAEncryption (RFC 8017 appendix A.2.4).
  internal static let sha512WithRsa = "1.2.840.113549.1.1.13"

  /// id-RSASSA-PSS (RFC 8017 appendix A.4.3).
  internal static let rsaPss = "1.2.840.113549.1.1.10"

  /// rsaEncryption (RFC 8017 appendix A.2.1).
  internal static let rsaEncryption = "1.2.840.113549.1.1.1"

  /// id-mgf1 (RFC 8017 appendix A.2.1).
  internal static let maskGenerationFunction1 = "1.2.840.113549.1.1.8"

  /// SHA-1, the OCSP CertID hash (RFC 6960 mandates support).
  internal static let sha1 = "1.3.14.3.2.26"

  /// id-pkix-ocsp-nonce (RFC 8954).
  internal static let ocspNonce = "1.3.6.1.5.5.7.48.1.2"

  /// id-pe-authorityInfoAccess (RFC 5280 §4.2.2.1).
  internal static let authorityInfoAccess = "1.3.6.1.5.5.7.1.1"

  /// id-ad-caIssuers: where to fetch the issuer's certificate.
  internal static let caIssuers = "1.3.6.1.5.5.7.48.2"

  /// id-ad-ocsp: where to ask for revocation status.
  internal static let ocsp = "1.3.6.1.5.5.7.48.1"

  /// id-pkix-ocsp-basic (RFC 6960).
  internal static let ocspBasic = "1.3.6.1.5.5.7.48.1.1"

  /// id-pkix-ocsp-nocheck (RFC 6960 §4.2.2.2.1).
  internal static let ocspNoCheck = "1.3.6.1.5.5.7.48.1.5"

  /// id-ce-extKeyUsage (RFC 5280 §4.2.1.12).
  internal static let extendedKeyUsage = "2.5.29.37"

  /// id-ce-basicConstraints (RFC 5280 §4.2.1.9).
  internal static let basicConstraints = "2.5.29.19"

  /// id-ce-keyUsage (RFC 5280 §4.2.1.3).
  internal static let keyUsage = "2.5.29.15"

  /// id-ce-subjectKeyIdentifier (RFC 5280 §4.2.1.2).
  internal static let subjectKeyIdentifier = "2.5.29.14"

  /// X.509 subjectAltName extension.
  internal static let subjectAltName = "2.5.29.17"

  /// Extended key usage: TLS server authentication.
  internal static let serverAuthentication = "1.3.6.1.5.5.7.3.1"

  /// Elliptic-curve public key (SPKI algorithm).
  internal static let ecPublicKey = "1.2.840.10045.2.1"

  /// The P-256 named curve.
  internal static let prime256v1 = "1.2.840.10045.3.1.7"

  /// id-ce-cRLDistributionPoints (RFC 5280 section 4.2.1.13).
  internal static let crlDistributionPoints = "2.5.29.31"

  /// id-kp-OCSPSigning (RFC 6960 §4.2.2.2).
  internal static let ocspSigning = "1.3.6.1.5.5.7.3.9"

  /// id-kp-timeStamping (RFC 5280).
  internal static let timestampingKeyPurpose = "1.3.6.1.5.5.7.3.8"

  /// id-ri-ocsp-response, an OCSPResponse carried as
  /// OtherRevocationInfoFormat (RFC 5940 section 4.1).
  internal static let otherRevocationInfoOcspResponse = "1.3.6.1.5.5.7.16.2"

  /// id-signingTime (RFC 5652 section 11.3).
  internal static let signingTime = "1.2.840.113549.1.9.5"
}
