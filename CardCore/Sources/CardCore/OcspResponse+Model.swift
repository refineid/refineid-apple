// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CryptoKit
import Foundation
import Security

extension OcspResponse {
  /// The parts of a response after its outer status envelope is checked.
  internal struct BasicResponse {
    /// The DER bytes containing the BasicOCSPResponse.
    internal let encoded: Data

    /// Parsed data that the signature covers.
    internal let responseData: ResponseData

    /// The AlgorithmIdentifier in the BasicOCSPResponse.
    internal let signatureAlgorithm: DerReader.Element

    /// The signature bytes without the BIT STRING unused-bits count.
    internal let signature: Data

    /// Any responder certificates carried by the response.
    internal let certificates: [Data]
  }

  /// The definitive per-certificate statuses.
  internal enum CertificateStatus {
    /// The certificate was good at `thisUpdate`.
    case good

    /// The certificate was revoked at `revokedAt`, for `reason` when
    /// the responder names a known one.
    case revoked(revokedAt: Date, reason: RevocationReason?)

    /// The responder cannot determine the certificate status.
    case unknown
  }

  /// The values that must exactly match the CertID in the answer.
  internal struct ExpectedCertId {
    /// The target certificate's encoded issuer Name.
    internal let issuerName: Data

    /// The issuer certificate's subjectPublicKey bits.
    internal let issuerKey: Data

    /// The target certificate's serial INTEGER value octets.
    internal let serialNumber: Data

    /// Builds the expected RFC 6960 certificate identifier.
    internal init(target: CertificateFacts, issuer: CertificateFacts) {
      issuerName = target.issuerName
      issuerKey = issuer.publicKeyBits
      serialNumber = target.serialNumber
    }

    /// The issuer Name and key hashes under the CertID hash algorithm
    /// `oid`: SHA-1 or SHA-256 (RFC 6960 section 4.1.1), nil for any
    /// other.
    internal func hashes(underAlgorithm oid: Data) -> (name: Data, key: Data)? {
      switch oid {
      case DerEncoder.objectIdentifier(SignOids.sha1):
        (
          Data(Insecure.SHA1.hash(data: issuerName)),
          Data(Insecure.SHA1.hash(data: issuerKey))
        )

      case DerEncoder.objectIdentifier(SignOids.sha256):
        (Data(SHA256.hash(data: issuerName)), Data(SHA256.hash(data: issuerKey)))

      default:
        nil
      }
    }
  }

  /// One X.509 extension, preserving the unwrapped extnValue bytes.
  internal struct Extension {
    /// Whether the extension is marked critical.
    internal let critical: Bool

    /// The DER-encoded extension OID.
    internal let oid: Data

    /// The content of the extension's outer OCTET STRING.
    internal let value: Data
  }

  /// A certificate accompanied by the fields response validation needs.
  internal struct ParsedCertificate {
    /// The Security representation used for trust and signature checks.
    internal let certificate: SecCertificate

    /// The exact DER certificate.
    internal let der: Data

    /// Raw fields used in CertID and ResponderID comparisons.
    internal let facts: CertificateFacts

    /// Parses a certificate once at the trust boundary.
    internal init(der: Data) throws {
      guard
        let parsedCertificate = SecCertificateCreateWithData(nil, der as CFData),
        let parsedFacts = CertificateFacts(der: der)
      else {
        throw ValidationFailure.certificateUnparseable
      }
      self.certificate = parsedCertificate
      self.der = der
      self.facts = parsedFacts
    }
  }

  /// One parsed SingleResponse, including whether it names the target.
  internal struct ParsedSingleResponse {
    /// Whether CertID exactly identifies the requested certificate.
    internal let matches: Bool

    /// The response validity end when provided.
    internal let nextUpdate: Date?

    /// The response status.
    internal let status: CertificateStatus

    /// The response validity start.
    internal let thisUpdate: Date
  }

  /// The responder identity forms RFC 6960 permits.
  internal enum ResponderId {
    /// SHA-1 over the responder certificate's subjectPublicKey bits.
    case keyHash(Data)

    /// The responder certificate's subject Name, DER encoded.
    case name(Data)

    /// Whether this identity belongs to a certificate.
    internal func matches(_ facts: CertificateFacts) -> Bool {
      switch self {
      case .keyHash(let hash):
        hash == Data(Insecure.SHA1.hash(data: facts.publicKeyBits))

      case .name(let name):
        name == facts.subjectName
      }
    }
  }

  /// The authorization result for one candidate response signer.
  internal enum ResponderAuthorization {
    /// The signer is permitted to answer for the requested issuer.
    case authorized

    /// The signer is delegated, but needs separate revocation evidence.
    case revocationCheckRequired

    /// The signer has no delegated authority for this issuer.
    case unauthorized
  }

  /// The data directly signed by the responder.
  internal struct ResponseData {
    /// The time by which the responder says newer information is available.
    internal let nextUpdate: Date?

    /// The responder's signed production time.
    internal let producedAt: Date

    /// The complete DER ResponseData encoding, exactly as signed.
    internal let raw: Data

    /// The responder identity named in the response.
    internal let responderId: ResponderId

    /// The matched response's certificate status.
    internal let status: CertificateStatus

    /// The matched response's status freshness start.
    internal let thisUpdate: Date
  }
}
