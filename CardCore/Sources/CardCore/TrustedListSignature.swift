// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// Verifies the enveloped XAdES signature of a trusted list (TS 119 612
/// clause 5.7.1, annex A.1 and annex B.1; W3C XML Signature 1.1
/// section 6.6.4).
///
/// `ds:SignedInfo` carries exactly two `ds:Reference`s (annex B): one to
/// the list and one to the signed properties; any other count is
/// refused before anything is computed. The signer is the `ds:KeyInfo`
/// certificate the `SigningCertificate` property names (annex B.1.1),
/// compared byte for byte with the certificates entitled to sign the
/// list, and the `ds:SignedInfo` signature is verified under it before
/// any reference is recomputed, so a forged list costs one signature
/// verification. Then both references are: the one to the list carries
/// the enveloped-signature transform and then at most one
/// canonicalisation, and digests the list without the signature (annex
/// B.1 rule 2); the other, of the `SignedProperties` type, digests this
/// signature's signed properties under its canonicalisation. A
/// reference elsewhere cannot be recomputed and fails the signature.
/// The signer certificate's own validity and revocation are not
/// consulted: the lists are a direct trust model in which issuing a new
/// list deprecates the old one (annex A.2).
internal enum TrustedListSignature {
  /// What `ds:SignedInfo` states.
  internal struct SignedInfo {
    /// The element itself.
    internal let element: XmlElement

    /// Its two references: to the list, then to the signed properties.
    internal let references: [XmlElement]

    /// How the element is canonicalised before signing.
    internal let canonicalization: XmlCanonicalization

    /// The signature algorithm.
    internal let method: XmlSignatureMethod
  }

  /// The enveloped-signature transform (XML Signature 1.1 section
  /// 6.6.4).
  internal static let envelopedSignatureTransform =
    "http://www.w3.org/2000/09/xmldsig#enveloped-signature"

  /// The references `ds:SignedInfo` carries (annex B).
  internal static let referenceCount = 2

  /// Verifies `signature`, enveloped in `root`, the list, and returns
  /// the signer certificate, one of `signers`.
  internal static func verify(
    document: XmlDocument,
    root: XmlElement,
    signature: XmlElement,
    signers: [Data]
  ) throws -> Data {
    let signedInfo = try Self.signedInfo(of: signature)
    let value = try Self.signatureValue(of: signature)
    let signedProperties = try Self.signedProperties(of: signature)
    let signer = try Self.signer(of: signature, bound: signedProperties)
    guard signers.contains(signer) else { throw TrustedListError.signerNotEntitled }
    guard
      let canonical = XmlCanonicalizer.canonicalize(
        signedInfo.element, method: signedInfo.canonicalization, omitting: nil)
    else {
      throw TrustedListError.unverifiable("SignedInfo canonicalisation")
    }
    guard signedInfo.method.verifies(value, over: canonical, certificate: signer) else {
      throw TrustedListError.signatureInvalid
    }
    try Self.checkReferences(
      signedInfo.references,
      document: document,
      root: root,
      signature: signature,
      signedProperties: signedProperties
    )
    return signer
  }

  /// The `ds:SignedInfo` of `signature`, with exactly two references
  /// and a canonicalisation and signature method the verifier
  /// computes.
  private static func signedInfo(of signature: XmlElement) throws -> SignedInfo {
    guard
      let element = signature.child(XadesSignature.namespaceDsig, XadesXmlParser.Element.signedInfo)
    else {
      throw TrustedListError.malformed("no SignedInfo")
    }
    let references = element.children(
      XadesSignature.namespaceDsig, XadesXmlParser.Element.reference)
    guard references.count == Self.referenceCount else {
      throw TrustedListError.malformed("SignedInfo does not carry exactly two references")
    }
    let canonicalizationElement = element.child(
      XadesSignature.namespaceDsig, XadesXmlParser.Element.canonicalizationMethod)
    guard
      let canonicalization = canonicalizationElement.flatMap({ method in
        XmlCanonicalization(method: method)
      })
    else {
      throw TrustedListError.unverifiable("SignedInfo canonicalisation")
    }
    let methodElement = element.child(
      XadesSignature.namespaceDsig, XadesXmlParser.Element.signatureMethod)
    guard
      let uri = methodElement?.attribute(XadesXmlParser.Attribute.algorithm),
      let method = XmlSignatureMethod(uri: uri)
    else {
      throw TrustedListError.unverifiable("signature algorithm")
    }
    return SignedInfo(
      element: element, references: references, canonicalization: canonicalization, method: method)
  }

  /// The decoded `ds:SignatureValue`.
  private static func signatureValue(of signature: XmlElement) throws -> Data {
    guard
      let element = signature.child(
        XadesSignature.namespaceDsig, XadesXmlParser.Element.signatureValue)
    else {
      throw TrustedListError.malformed("no SignatureValue")
    }
    guard let value = XadesXmlParser.base64(element.text) else {
      throw TrustedListError.malformed("SignatureValue is not base64")
    }
    return value
  }

  /// This signature's `xades:SignedProperties`.
  internal static func signedProperties(of signature: XmlElement) throws -> XmlElement {
    let found = signature.children(XadesSignature.namespaceDsig, XadesXmlParser.Element.object)
      .compactMap { object in
        object.child(XadesSignature.namespaceXades, XadesXmlParser.Element.qualifyingProperties)
      }
      .compactMap { properties in
        properties.child(XadesSignature.namespaceXades, XadesXmlParser.Element.signedProperties)
      }
    guard let properties = found.first else {
      throw TrustedListError.malformed("no SignedProperties")
    }
    return properties
  }

  /// The `ds:KeyInfo` certificate the signing-certificate property of
  /// `bound` names.
  private static func signer(of signature: XmlElement, bound properties: XmlElement) throws -> Data
  {
    let keyInfo =
      try signature
      .children(XadesSignature.namespaceDsig, XadesXmlParser.Element.keyInfo)
      .flatMap { keyInfo in
        keyInfo.children(XadesSignature.namespaceDsig, XadesXmlParser.Element.x509Data)
      }
      .flatMap { data in
        data.children(XadesSignature.namespaceDsig, XadesXmlParser.Element.x509Certificate)
      }
      .map { certificate in
        guard let der = XadesXmlParser.base64(certificate.text) else {
          throw TrustedListError.malformed("X509Certificate is not base64")
        }
        return der
      }
    let signed = properties.child(
      XadesSignature.namespaceXades, XadesXmlParser.Element.signedSignatureProperties)
    guard
      let binding = signed?.child(
        XadesSignature.namespaceXades, XadesXmlParser.Element.signingCertificateV2)
        ?? signed?.child(XadesSignature.namespaceXades, XadesXmlParser.Element.signingCertificate)
    else {
      throw TrustedListError.malformed("no SigningCertificate")
    }
    let cert = binding.child(XadesSignature.namespaceXades, XadesXmlParser.Element.cert)
    guard
      let digestParent = cert?.child(
        XadesSignature.namespaceXades, XadesXmlParser.Element.certDigest)
    else {
      throw TrustedListError.malformed("SigningCertificate without a readable CertDigest")
    }
    let digest = try XmlDigestValue(
      parent: digestParent, what: "SigningCertificate without a readable CertDigest")
    guard let signer = keyInfo.first(where: digest.matches) else {
      throw TrustedListError.malformed("SigningCertificate names no KeyInfo certificate")
    }
    return signer
  }
}
