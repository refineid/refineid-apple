// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

extension OcspResponse {
  /// RFC 9654 caps a nonce at 128 octets; this product sends 32.
  internal static let maximumNonceByteCount = 128

  /// A response without `nextUpdate` cannot be accepted indefinitely.
  ///
  /// RFC 6960 leaves the meaning of an omitted `nextUpdate` to the
  /// relying party. Seven days is deliberately conservative for the
  /// validation material collected during a signing ceremony.
  internal static let maximumAgeWithoutNextUpdate: TimeInterval = 604_800

  /// Clock difference tolerated between the responder and this device.
  ///
  /// A small allowance avoids rejecting fresh evidence merely because
  /// the two independently operated clocks differ by a few minutes.
  internal static let maximumClockSkew: TimeInterval = 300

  /// SHA-1 output length, used by RFC 6960 CertID and ResponderID.
  internal static let sha1DigestByteCount = 20

  /// Checks one `OCSPResponse` against the certificate and issuer used to
  /// construct the request.
  ///
  /// `currentTime` is explicit so a caller that is preserving long-term
  /// evidence can apply the verification time it has authenticated rather
  /// than accidentally consulting a wall clock from a different moment.
  public static func validate(
    response: Data,
    certificate: Data,
    issuerCertificate: Data,
    nonce: Data,
    currentTime: Date
  ) throws -> Validity {
    guard !nonce.isEmpty, nonce.count <= Self.maximumNonceByteCount else {
      throw ValidationFailure.nonceMalformed
    }
    let target = try ParsedCertificate(der: certificate)
    let issuer = try ParsedCertificate(der: issuerCertificate)
    try Self.checkTargetIssuerName(target, issuer: issuer)

    let expected = ExpectedCertId(target: target.facts, issuer: issuer.facts)
    let basic = try Self.basicResponse(from: response, expected: expected, nonce: nonce)
    try Self.checkTimes(basic.responseData, against: currentTime)
    try Self.checkTargetIssuerSignature(
      target,
      issuer: issuer,
      at: basic.responseData.producedAt
    )
    let algorithm = try Self.signatureAlgorithm(
      in: basic.encoded,
      element: basic.signatureAlgorithm
    )
    let responders = try Self.authorizedResponders(in: basic, issuer: issuer)
    return try Self.verifiedValidity(
      basic,
      signers: responders,
      algorithm: algorithm
    )
  }

  /// Confirms that the supplied issuer's normalized subject names the target.
  private static func checkTargetIssuerName(
    _ target: ParsedCertificate,
    issuer: ParsedCertificate
  ) throws {
    guard Self.issuer(of: target.certificate) == Self.subject(of: issuer.certificate) else {
      throw ValidationFailure.issuerMismatch
    }
  }

  /// Cryptographically proves the target was directly signed by the issuer.
  private static func checkTargetIssuerSignature(
    _ target: ParsedCertificate,
    issuer: ParsedCertificate,
    at producedAt: Date
  ) throws {
    guard
      CertificateIssuer.isDirectlyIssued(
        target.der,
        by: issuer.der,
        at: producedAt
      )
    else {
      throw ValidationFailure.issuerMismatch
    }
  }

  /// Finds matching signer certificates and enforces delegated authority.
  private static func authorizedResponders(
    in basic: BasicResponse,
    issuer: ParsedCertificate
  ) throws -> [ParsedCertificate] {
    let embedded = try basic.certificates.map(ParsedCertificate.init(der:))
    let candidates =
      [issuer]
      + embedded.filter { certificate in
        certificate.der != issuer.der
      }
    let matching = candidates.filter { candidate in
      basic.responseData.responderId.matches(candidate.facts)
    }
    guard !matching.isEmpty else {
      throw ValidationFailure.responderUnidentified
    }

    var responders: [ParsedCertificate] = []
    var revocationCheckRequired = false
    for signer in matching {
      switch try Self.authorization(signer, by: issuer, at: basic.responseData.producedAt) {
      case .authorized:
        responders.append(signer)

      case .revocationCheckRequired:
        revocationCheckRequired = true

      case .unauthorized:
        continue
      }
    }
    guard !responders.isEmpty else {
      if revocationCheckRequired {
        throw ValidationFailure.responderRevocationUnchecked
      }
      throw ValidationFailure.responderUnauthorized
    }
    return responders
  }

  /// Verifies an authorized responder signature and returns its status result.
  private static func verifiedValidity(
    _ basic: BasicResponse,
    signers: [ParsedCertificate],
    algorithm: SecKeyAlgorithm
  ) throws -> Validity {
    for signer in signers {
      guard
        Self.signatureIsValid(
          basic.signature,
          over: basic.responseData.raw,
          with: signer.certificate,
          algorithm: algorithm
        )
      else {
        continue
      }
      return try Self.statusValidity(from: basic.responseData)
    }
    throw ValidationFailure.signatureInvalid
  }

  /// Maps an authenticated single-response status to this verifier's result.
  private static func statusValidity(from response: ResponseData) throws -> Validity {
    switch response.status {
    case .good:
      return Validity(
        nextUpdate: response.nextUpdate,
        producedAt: response.producedAt,
        thisUpdate: response.thisUpdate
      )

    case .revoked:
      throw ValidationFailure.revoked

    case .unknown:
      throw ValidationFailure.unknown
    }
  }
}

extension OcspResponse {
  /// The status one authenticated OCSP response embedded as evidence
  /// gives one certificate.
  internal enum EvidenceStatus {
    /// Good at `thisUpdate`.
    case good

    /// Revoked at `revokedAt`, for `reason` when one is named.
    case revoked(revokedAt: Date, reason: RevocationReason?)
  }

  /// What one authenticated OCSP response says about one certificate,
  /// before any time window is applied.
  internal struct Evidence {
    /// The responder's producedAt.
    internal let producedAt: Date

    /// The single response's thisUpdate.
    internal let thisUpdate: Date

    /// The single response's nextUpdate, when present.
    internal let nextUpdate: Date?

    /// The answered status.
    internal let status: EvidenceStatus
  }

  /// Authenticates `response` as evidence for `certificate` under
  /// `issuer`, whose relationship the caller's certificate path
  /// already proved.
  ///
  /// The CertID, the responder's identity and authority at producedAt,
  /// and its signature are checked as for a live answer; no nonce is
  /// expected, and no time window is applied here. An unknown status
  /// speaks for nothing and throws.
  internal static func evidence(
    response: Data,
    certificate: Data,
    issuerCertificate: Data
  ) throws -> Evidence {
    let target = try ParsedCertificate(der: certificate)
    let issuer = try ParsedCertificate(der: issuerCertificate)
    guard Self.issuer(of: target.certificate) == Self.subject(of: issuer.certificate) else {
      throw ValidationFailure.issuerMismatch
    }
    let expected = ExpectedCertId(target: target.facts, issuer: issuer.facts)
    let basic = try Self.basicResponse(from: response, expected: expected, nonce: nil)
    let algorithm = try Self.signatureAlgorithm(
      in: basic.encoded,
      element: basic.signatureAlgorithm
    )
    let responders = try Self.authorizedResponders(in: basic, issuer: issuer)
    guard
      responders.contains(where: { signer in
        Self.signatureIsValid(
          basic.signature,
          over: basic.responseData.raw,
          with: signer.certificate,
          algorithm: algorithm
        )
      })
    else {
      throw ValidationFailure.signatureInvalid
    }
    let status: EvidenceStatus
    switch basic.responseData.status {
    case .good:
      status = .good

    case .revoked(let revokedAt, let reason):
      status = .revoked(revokedAt: revokedAt, reason: reason)

    case .unknown:
      throw ValidationFailure.unknown
    }
    return Evidence(
      producedAt: basic.responseData.producedAt,
      thisUpdate: basic.responseData.thisUpdate,
      nextUpdate: basic.responseData.nextUpdate,
      status: status
    )
  }
}
