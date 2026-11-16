// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

/// The dedicated home for SCS wire values.
///
/// Source: the DVV SCS specification v1.3 (Signature Creation Service),
/// the localhost signing interface Finnish web services call at
/// `https://127.0.0.1:53952`. Protocol logic lives beside the other
/// card-facing protocol models; these are the named constants it
/// composes from.
internal enum ScsValues {
  /// The one TCP port the specification names (v1.3 §2.2).
  internal static let port: UInt16 = 53_952

  /// The protocol version this service implements and answers in
  /// every response body.
  internal static let version = "1.3"

  /// Smallest accepted authentication-challenge nonce, in octets
  /// (v1.3 §3.7).
  internal static let nonceMinimumLength = 64

  /// JWE initialization-vector length for A256GCM: 96 bits.
  internal static let jweInitializationVectorLength = 12

  /// JWE authentication-tag length for A256GCM: 128 bits.
  internal static let jweTagLength = 16

  /// Reason code: signature generated (v1.3 §2.6.3).
  internal static let reasonOk = 200

  /// Reason code: malformed request.
  internal static let reasonBadRequest = 400

  /// Reason code: end-user or credential refusal.
  internal static let reasonUnauthorized = 401

  /// Reason code: request refused by policy (origin or challenge
  /// binding).
  internal static let reasonForbidden = 403

  /// Reason code: internal failure.
  internal static let reasonInternalError = 500

  /// Reason code: valid request for an unimplemented capability.
  internal static let reasonNotImplemented = 501

  /// HTTP status: OK.
  ///
  /// The SCS answers 200 even for failed signs; the JSON reason
  /// triple carries the outcome (v1.3 §3).
  internal static let httpOk = 200

  /// HTTP status: Forbidden, answered when CORS or Origin policy
  /// refuses a non-sign request before route handling.
  internal static let httpForbidden = 403

  /// HTTP status: no route.
  internal static let httpNotFound = 404

  /// Longest accepted HTTP head, in bytes; a longer one is not a
  /// well-formed SCS exchange.
  internal static let httpHeadMaximumLength = 65_536

  /// Longest accepted HTTP body, in bytes: 100 MiB (v1.3 §2.1).
  internal static let httpBodyMaximumLength = 104_857_600

  /// CORS preflight cache lifetime, in seconds.
  internal static let preflightMaxAgeSeconds = 600

  /// Maximum lifetime of an agreed transaction awaiting `execute`, in
  /// seconds.
  internal static let transactionTimeToLiveSeconds: Double = 60

  /// Sliding-window length for per-origin prompt throttling, in
  /// seconds.
  internal static let promptWindowSeconds: Double = 60

  /// Maximum PIN prompts one origin may trigger inside one window.
  internal static let promptMaximumPerWindow = 5

  /// Cooldown imposed on an origin after a cancelled or refused PIN
  /// prompt, in seconds.
  internal static let promptRefusalCooldownSeconds: Double = 10

  /// Maximum distinct origin buckets held in the prompt rate limiter.
  internal static let promptMaxTrackedOrigins = 128

  /// Maximum characters displayed for an Origin in the consent prompt.
  internal static let originDisplayMaximumCharacters = 96

  /// Compact JWS segment count: header, payload, signature.
  internal static let jwsSegmentCount = 3

  /// Compact JWS segment index of the signature.
  internal static let jwsSignatureIndex = 2

  /// Compact JWE segment count: header, empty key, IV, ciphertext,
  /// tag (direct encryption leaves the key segment empty).
  internal static let jweSegmentCount = 5

  /// Compact JWE segment index of the initialization vector.
  internal static let jweInitializationVectorIndex = 2

  /// Compact JWE segment index of the ciphertext.
  internal static let jweCiphertextIndex = 3

  /// Compact JWE segment index of the authentication tag.
  internal static let jweTagIndex = 4

  /// KeyUsage bits of the localhost server leaf certificate:
  /// digitalSignature and keyEncipherment (v1.3 §2.3).
  internal static let serverKeyUsageBits: UInt8 = 0xA0

  /// Unused trailing bits in the server leaf KeyUsage BIT STRING.
  internal static let serverKeyUsageUnusedBits: UInt8 = 5

  /// KeyUsage bits of the offline localhost root CA certificate:
  /// keyCertSign and cRLSign (RFC 5280 §4.2.1.3).
  internal static let rootKeyUsageBits: UInt8 = 0x06

  /// Unused trailing bits in the root CA KeyUsage BIT STRING.
  internal static let rootKeyUsageUnusedBits: UInt8 = 1

  /// Full-host subnet mask octet in RFC 5280 NameConstraints.
  private static let fullMaskOctet: UInt8 = 0xFF

  /// High octet of the IPv4 loopback address.
  private static let loopbackHighOctet: UInt8 = 0x7F

  /// IPv6 zero prefix length before the loopback low byte.
  private static let ipv6LoopbackLeadingZeros = 15

  /// IPv6 address octet count.
  private static let ipv6AddressOctetCount = 16

  /// Serial number entropy length, in octets.
  internal static let serialOctetCount = 16

  /// High-bit mask cleared on the leading serial-number octet.
  internal static let serialPositiveMask: UInt8 = 0x7F

  /// Fallback low bit set when random serial octets are all zero.
  internal static let serialNonZeroBit: UInt8 = 0x01

  /// How long a generated offline root CA certificate stays valid, in
  /// years.
  internal static let rootCertificateValidityYears = 10

  /// How long a generated localhost server leaf stays valid, in days.
  internal static let leafCertificateValidityDays = 397

  /// Remaining leaf validity below which the server rotates its
  /// localhost chain, in seconds (30 days).
  internal static let leafRotationMarginSeconds: Double = 2_592_000

  /// Clock-skew allowance subtracted from `notBefore`, in seconds.
  internal static let notBeforeClockSkewSeconds: Double = 60

  /// RFC 5280 §4.1.2.5 year at which GeneralizedTime replaces UTCTime.
  internal static let generalizedTimeCutoffYear = 2_050

  /// The loopback address named in the certificate's
  /// subjectAltName (v1.3 §2.3): 127.0.0.1.
  internal static var loopbackAddress: [UInt8] {
    [Self.loopbackHighOctet, 0, 0, 1]
  }

  /// The IPv4 NameConstraints subtree `127.0.0.1/32` (RFC 5280
  /// §4.2.1.10).
  internal static var loopbackNameConstraint: [UInt8] {
    Self.loopbackAddress + Array(repeating: Self.fullMaskOctet, count: 4)
  }

  /// The IPv6 NameConstraints subtree `::1/128` (RFC 5280 §4.2.1.10).
  internal static var ipv6LoopbackNameConstraint: [UInt8] {
    Array(repeating: UInt8(0), count: Self.ipv6LoopbackLeadingZeros)
      + [1]
      + Array(repeating: Self.fullMaskOctet, count: Self.ipv6AddressOctetCount)
  }

  /// Whether a Unicode scalar value is a control, line-break, zero-width,
  /// or bidirectional-override character excluded from displayed Origins.
  internal static func isForbiddenOriginScalar(_ value: UInt32) -> Bool {
    switch value {
    case 0x0000...0x001F,
      0x007F...0x009F,
      0x061C,
      0x200B...0x200F,
      0x2028...0x202E,
      0x2060...0x2069,
      0xFEFF:
      true

    default:
      false
    }
  }
}
