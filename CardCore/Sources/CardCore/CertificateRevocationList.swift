// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation
import Security

/// Authenticates one full, direct X.509 certificate revocation list.
///
/// A downloaded CRL is usable validation material only after its issuer,
/// signature, validity window, scope, and target serial number have all been
/// checked. Delta and indirect CRLs need state that this verifier deliberately
/// does not infer, so they fail closed instead of being stored as full lists.
public enum CertificateRevocationList {
  /// Why a CRL cannot be relied upon for the supplied certificate.
  public enum ValidationFailure: Error, Equatable {
    /// The subject or issuer certificate did not parse.
    case certificateUnparseable

    /// The input is a delta CRL rather than a complete revocation list.
    case deltaUnsupported

    /// The CRL or one of its entries uses indirect-CRL semantics.
    case indirectUnsupported

    /// The supplied issuer does not issue the certificate or the CRL.
    case issuerMismatch

    /// The issuer certificate does not authorize its key to sign CRLs.
    case issuerUnauthorized

    /// The CRL's validity interval is reversed or no longer current.
    case listExpired

    /// The CRL was issued after the caller's explicit verification time.
    case listFromFuture

    /// The CRL is not one exact DER value with the required X.509 structure.
    case malformed

    /// The CRL omits the freshness boundary required by this product.
    case nextUpdateMissing

    /// The target certificate's serial number occurs in the authenticated CRL.
    case revoked

    /// The issuing distribution point restricts which certificates it covers.
    case scopeUnsupported

    /// The issuer did not make the signature over the exact TBSCertList bytes.
    case signatureInvalid

    /// A critical extension has semantics this verifier does not implement.
    case unsupportedCriticalExtension

    /// The CRL uses a signature algorithm this verifier does not support.
    case unsupportedSignatureAlgorithm
  }

  /// Authenticated CRL facts safe for the validation-material store.
  public struct Validity: Equatable, Sendable {
    /// The canonical DER CRL, including when the input used a PEM envelope.
    public let encoded: Data

    /// The time at which the issuer says the list became current.
    public let thisUpdate: Date

    /// The time by which the issuer says a replacement list will be available.
    public let nextUpdate: Date
  }

  /// Parsed certificate information needed for CRL authentication.
  internal struct CertificateContext {
    /// Security's certificate handle, used for name and key operations.
    internal let certificate: SecCertificate

    /// The certificate serial as an unsigned, minimally represented magnitude.
    internal let serialNumber: Data

    /// The subject Name's exact DER encoding.
    internal let subjectName: Data

    /// Whether KeyUsage permits CRL signing (including when it is absent).
    internal let canSignCrl: Bool
  }

  /// One parsed full CRL and the bytes covered by its signature.
  internal struct ParsedList {
    /// The complete TBSCertList DER encoding.
    internal let signedData: Data

    /// The outer signature AlgorithmIdentifier DER encoding.
    internal let signatureAlgorithm: Data

    /// Signature bits without the BIT STRING unused-bit-count octet.
    internal let signature: Data

    /// The CRL issuer Name's exact DER encoding.
    internal let issuerName: Data

    /// The start of the advertised validity interval.
    internal let thisUpdate: Date

    /// The end of the advertised validity interval, when the list
    /// states one (RFC 5280 section 5.1.2.5).
    internal let nextUpdate: Date?

    /// The target serial's revoked entry, when the list carries one.
    internal let targetRevocation: RevokedEntry?
  }

  /// One revoked entry for the requested serial.
  internal struct RevokedEntry {
    /// The entry's revocationDate.
    internal let revokedAt: Date

    /// The entry's reasonCode extension, when present and known.
    internal let reason: RevocationReason?
  }

  /// Fields extracted from the signed TBSCertList before authentication.
  internal struct TbsFields {
    /// The signature AlgorithmIdentifier repeated in TBSCertList.
    internal let signatureAlgorithm: Data

    /// The exact issuer Name DER encoding.
    internal let issuerName: Data

    /// The start of the advertised validity interval.
    internal let thisUpdate: Date

    /// The end of the advertised validity interval when present.
    internal let nextUpdate: Date?

    /// The requested certificate's revoked entry, when present.
    internal let targetRevocation: RevokedEntry?
  }

  /// Required fields at the beginning of a TBSCertList.
  internal struct TbsHeader {
    /// The signature AlgorithmIdentifier repeated in TBSCertList.
    internal let signatureAlgorithm: Data

    /// The exact issuer Name DER encoding.
    internal let issuerName: Data

    /// The start of the advertised validity interval.
    internal let thisUpdate: Date

    /// Whether the CRL declares the version 2 syntax.
    internal let isVersionTwo: Bool
  }

  /// One parsed X.509 Extension.
  internal struct ExtensionValue {
    /// The complete DER OBJECT IDENTIFIER encoding.
    internal let identifier: Data

    /// Whether an implementation must understand the extension.
    internal let isCritical: Bool

    /// The DER value carried inside extnValue's OCTET STRING.
    internal let value: Data
  }

  /// The calendar fields extracted from an RFC 5280 Time.
  internal struct TimeFields {
    /// Four-digit Gregorian year.
    internal let year: Int

    /// Gregorian month number.
    internal let month: Int

    /// Gregorian day of month.
    internal let day: Int

    /// UTC hour.
    internal let hour: Int

    /// UTC minute.
    internal let minute: Int

    /// UTC second.
    internal let second: Int
  }

  /// Validates a DER or standard `X509 CRL` PEM response.
  ///
  /// `currentTime` is explicit so evidence collection never changes meaning
  /// because a wall clock was consulted at some later processing stage.
  public static func validate(
    crl: Data,
    certificate: Data,
    issuerCertificate: Data,
    currentTime: Date
  ) throws -> Validity {
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
    guard let nextUpdate = parsed.nextUpdate else {
      throw ValidationFailure.nextUpdateMissing
    }
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
    try Self.checkTimes(parsed, nextUpdate: nextUpdate, against: currentTime)
    guard
      CertificateIssuer.isDirectlyIssued(
        certificate,
        by: issuerCertificate,
        at: currentTime
      )
    else {
      throw ValidationFailure.issuerMismatch
    }
    guard parsed.targetRevocation == nil else {
      throw ValidationFailure.revoked
    }
    return Validity(
      encoded: encoded,
      thisUpdate: parsed.thisUpdate,
      nextUpdate: nextUpdate
    )
  }
}
