// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation
import Security

/// A `ds:SignatureMethod` the trusted-list verifier computes (RFC 6931
/// sections 2.3 and 2.4), verified over the canonical `ds:SignedInfo`.
internal enum XmlSignatureMethod: Sendable {
  case ecdsaSha256
  case ecdsaSha384
  case ecdsaSha512
  case rsaPssSha256
  case rsaSha256
  case rsaSha384
  case rsaSha512

  /// RFC 6931 section 2.3: the RSA PKCS #1 v1.5 identifiers.
  private static let rsaSha256Uri = "http://www.w3.org/2001/04/xmldsig-more#rsa-sha256"
  private static let rsaSha384Uri = "http://www.w3.org/2001/04/xmldsig-more#rsa-sha384"
  private static let rsaSha512Uri = "http://www.w3.org/2001/04/xmldsig-more#rsa-sha512"

  /// RFC 6931 section 2.3.10: RSASSA-PSS with SHA-256 and MGF1.
  private static let rsaPssSha256Uri = "http://www.w3.org/2007/05/xmldsig-more#sha256-rsa-MGF1"

  /// RFC 6931 section 2.3.6: the ECDSA identifiers, whose signature
  /// value is the raw concatenation of `r` and `s`.
  private static let ecdsaSha256Uri = "http://www.w3.org/2001/04/xmldsig-more#ecdsa-sha256"
  private static let ecdsaSha384Uri = "http://www.w3.org/2001/04/xmldsig-more#ecdsa-sha384"
  private static let ecdsaSha512Uri = "http://www.w3.org/2001/04/xmldsig-more#ecdsa-sha512"

  /// The platform algorithm over the whole message.
  private var secKeyAlgorithm: SecKeyAlgorithm {
    switch self {
    case .ecdsaSha256:
      .ecdsaSignatureMessageX962SHA256

    case .ecdsaSha384:
      .ecdsaSignatureMessageX962SHA384

    case .ecdsaSha512:
      .ecdsaSignatureMessageX962SHA512

    case .rsaPssSha256:
      .rsaSignatureMessagePSSSHA256

    case .rsaSha256:
      .rsaSignatureMessagePKCS1v15SHA256

    case .rsaSha384:
      .rsaSignatureMessagePKCS1v15SHA384

    case .rsaSha512:
      .rsaSignatureMessagePKCS1v15SHA512
    }
  }

  /// Whether the XML signature value is the raw `r || s` of ECDSA,
  /// which the platform wants as X9.62 DER.
  private var isEcdsa: Bool {
    switch self {
    case .ecdsaSha256, .ecdsaSha384, .ecdsaSha512:
      true

    case .rsaPssSha256, .rsaSha256, .rsaSha384, .rsaSha512:
      false
    }
  }

  /// The method `uri` names, nil for every other identifier.
  internal init?(uri: String) {
    switch uri {
    case Self.rsaSha256Uri:
      self = .rsaSha256

    case Self.rsaSha384Uri:
      self = .rsaSha384

    case Self.rsaSha512Uri:
      self = .rsaSha512

    case Self.rsaPssSha256Uri:
      self = .rsaPssSha256

    case Self.ecdsaSha256Uri:
      self = .ecdsaSha256

    case Self.ecdsaSha384Uri:
      self = .ecdsaSha384

    case Self.ecdsaSha512Uri:
      self = .ecdsaSha512

    default:
      return nil
    }
  }

  /// The public key of `certificate`.
  ///
  /// The platform loads no key from a certificate whose
  /// SubjectPublicKeyInfo names id-RSASSA-PSS (RFC 4055 section 1.2), as
  /// the German list signer's does, though the subjectPublicKey is an
  /// ordinary RSAPublicKey (RFC 4055 section 1.2 and RFC 8017 appendix
  /// A.1.1). Under the PSS method such a key is built from those bits.
  private func publicKey(of certificate: Data) -> SecKey? {
    guard let parsed = SecCertificateCreateWithData(nil, certificate as CFData) else { return nil }
    if let key = SecCertificateCopyKey(parsed) { return key }
    guard self == .rsaPssSha256, let bits = CertificateFacts(der: certificate)?.publicKeyBits else {
      return nil
    }
    let attributes: [CFString: Any] = [
      kSecAttrKeyType: kSecAttrKeyTypeRSA,
      kSecAttrKeyClass: kSecAttrKeyClassPublic,
    ]
    return SecKeyCreateWithData(bits as CFData, attributes as CFDictionary, nil)
  }

  /// Whether `signature`, in the XML form, verifies over `message`
  /// under the public key of `certificate`.
  internal func verifies(_ signature: Data, over message: Data, certificate: Data) -> Bool {
    guard let key = publicKey(of: certificate) else { return false }
    let wire: Data
    if isEcdsa {
      guard let der = EcdsaSignature.derFromRawConcatenation(signature) else { return false }
      wire = der
    } else {
      wire = signature
    }
    var error: Unmanaged<CFError>?
    return SecKeyVerifySignature(key, secKeyAlgorithm, message as CFData, wire as CFData, &error)
  }
}
