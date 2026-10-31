// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CardCore
import Foundation

/// A verified revoked answer, mapped to its certificate path by the
/// caller.
internal struct AuthenticatedRevocation: Error {
  /// The authenticated answer that says revoked.
  internal let evidence: ValidationMaterialCollector.StatusEvidence
}

/// Revocation-evidence authentication for validation-material collection.
extension ValidationMaterialCollector {
  /// The result of trying every advertised OCSP responder.
  private struct OcspAttempt {
    /// One authenticated response, when available.
    let response: Data?

    /// Whether secure random generation prevented an OCSP request.
    let randomFailed: Bool
  }

  /// The OCSP request media type.
  private static let ocspContentType = "application/ocsp-request"

  /// Fetches and authenticates one current OCSP answer or full CRL.
  internal static func status(
    of subject: Data,
    facts: CertificateFacts,
    under issuer: Data,
    at currentTime: Date,
    dependencies: Dependencies
  ) async throws -> StatusEvidence {
    let ocsp = try await Self.ocspStatus(
      of: subject,
      facts: facts,
      under: issuer,
      at: currentTime,
      dependencies: dependencies
    )
    if let response = ocsp.response {
      return .ocsp(response)
    }
    if let list = try await Self.crlStatus(
      of: subject,
      facts: facts,
      under: issuer,
      at: currentTime,
      dependencies: dependencies
    ) {
      return .revocationList(list)
    }
    if ocsp.randomFailed {
      throw Failure.randomUnavailable
    }
    throw Failure.revocationUnavailable
  }

  /// Tries each OCSP service until one authentic current response arrives.
  private static func ocspStatus(
    of subject: Data,
    facts: CertificateFacts,
    under issuer: Data,
    at currentTime: Date,
    dependencies: Dependencies
  ) async throws -> OcspAttempt {
    guard let issuerFacts = CertificateFacts(der: issuer) else {
      throw Failure.certificateMalformed
    }
    for responder in Self.boundedCertificateAddresses(facts.ocspUrls) {
      guard
        let nonce = try? dependencies.random(OcspRequest.nonceByteCount)
      else {
        return OcspAttempt(response: nil, randomFailed: true)
      }
      let request = OcspRequest.encoded(
        issuerName: facts.issuerName,
        issuerKey: issuerFacts.publicKeyBits,
        serial: facts.serialNumber,
        nonce: nonce
      )
      guard
        let response = try? await dependencies.post(
          request, responder, Self.ocspContentType
        )
      else { continue }
      do {
        _ = try OcspResponse.validate(
          response: response,
          certificate: subject,
          issuerCertificate: issuer,
          nonce: nonce,
          currentTime: currentTime
        )
        return OcspAttempt(response: response, randomFailed: false)
      } catch OcspResponse.ValidationFailure.revoked {
        throw AuthenticatedRevocation(evidence: .ocsp(response))
      } catch {
        continue
      }
    }
    return OcspAttempt(response: nil, randomFailed: false)
  }

  /// Tries each advertised full CRL until one authentic current list arrives.
  private static func crlStatus(
    of subject: Data,
    facts: CertificateFacts,
    under issuer: Data,
    at currentTime: Date,
    dependencies: Dependencies
  ) async throws -> Data? {
    for address in Self.boundedCertificateAddresses(facts.crlUrls) {
      guard let response = try? await dependencies.get(address, true) else {
        continue
      }
      do {
        let validity = try CertificateRevocationList.validate(
          crl: response,
          certificate: subject,
          issuerCertificate: issuer,
          currentTime: currentTime
        )
        return validity.encoded
      } catch CertificateRevocationList.ValidationFailure.revoked {
        throw AuthenticatedRevocation(evidence: .revocationList(response))
      } catch {
        continue
      }
    }
    return nil
  }
}
