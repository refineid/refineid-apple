// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation
import Security

/// Verification of the `begin` transaction's compact JWS against the
/// relying service's certificate (DVV SCS specification v1.3; RFC
/// 7515).
///
/// The certificate rides in the payload itself; what verification
/// establishes is that the party who published the server key also
/// authorised this transaction, and that its certificate is inside
/// its validity window. Chain building is deliberately not attempted
/// here - the origin-bound challenge, not the certificate chain, is
/// what protects the holder.
public enum ScsJsonWebSignature {
  /// Raw ES256 JWS signatures are r||s at 64 bytes (RFC 7518
  /// section 3.4).
  private static let es256SignatureLength = 64

  /// Why the JWS is refused, or nil when it verifies at `now`.
  public static func refusal(
    algorithm: String,
    certificateDer: Data,
    signingInput: Data,
    signature: Data,
    at now: Date
  ) -> ScsTransactionError? {
    var outer = DerReader(certificateDer)
    guard
      let outerElement = outer.next(),
      outerElement.tag == DerValues.tagSequence,
      outer.isAtEnd,
      let certificate = SecCertificateCreateWithData(nil, certificateDer as CFData),
      let publicKey = SecCertificateCopyKey(certificate)
    else {
      return .badRequest("serverCert is not DER X.509")
    }
    if let validityRefusal = Self.validityRefusal(certificate: certificate, at: now) {
      return validityRefusal
    }
    let secAlgorithm: SecKeyAlgorithm
    var wireSignature = signature
    switch algorithm {
    case "RS256":
      secAlgorithm = .rsaSignatureMessagePKCS1v15SHA256

    case "ES256":
      guard
        signature.count == Self.es256SignatureLength,
        let der = EcdsaSignature.derFromRawConcatenation(signature)
      else {
        return .badRequest("ES256 signature is not raw r||s")
      }
      secAlgorithm = .ecdsaSignatureMessageX962SHA256
      wireSignature = der

    default:
      return .badRequest("unsupported JWS algorithm \(algorithm)")
    }
    guard
      SecKeyVerifySignature(
        publicKey,
        secAlgorithm,
        signingInput as CFData,
        wireSignature as CFData,
        nil
      )
    else {
      return .forbidden("begin transaction JWS signature is invalid")
    }
    return nil
  }

  /// Why the certificate's RFC 5280 validity window refuses `now`, or nil.
  private static func validityRefusal(
    certificate: SecCertificate,
    at now: Date
  ) -> ScsTransactionError? {
    guard let window = CertificateValidity.window(of: certificate) else {
      return .badRequest("serverCert has no readable validity window")
    }
    guard now >= window.notBefore, now <= window.notAfter else {
      return .forbidden("serverCert is not currently valid")
    }
    return nil
  }
}
