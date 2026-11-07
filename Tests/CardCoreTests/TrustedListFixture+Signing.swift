// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS)

  import CryptoKit
  import Foundation
  import Security
  import Testing

  @testable import CardCore

  /// Signing a synthetic list with an enveloped XAdES signature.
  extension TrustedListFixture {
    /// The width of one ECDSA P-256 signature half, in bytes.
    private static let p256HalfWidth = 32

    /// The exclusive canonical form of the element with `identifier` in
    /// `xml`, or of its root.
    internal static func canonical(_ xml: String, identifier: String?) throws -> Data {
      let document = try XmlDocument(Data(xml.utf8))
      let element: XmlElement
      if let identifier {
        element = try #require(document.element(withId: identifier))
      } else {
        element = document.root
      }
      return try #require(XmlCanonicalizer.canonicalize(element, method: .exclusive, omitting: nil))
    }

    /// The SHA-256 of `octets`, base64.
    internal static func digest(_ octets: Data) -> String {
      Data(SHA256.hash(data: octets)).base64EncodedString()
    }

    /// `unsigned`, a complete list without a signature, signed by
    /// `signer`.
    internal static func signed(_ unsigned: String, by signer: Operator) throws -> Data {
      let listDigest = Self.digest(try Self.canonical(unsigned, identifier: nil))
      let properties =
        #"<xades:SignedProperties Id="\#(Self.propertiesId)"><xades:SignedSignatureProperties>"#
        + "<xades:SigningTime>\(Self.issued)</xades:SigningTime>"
        + "<xades:SigningCertificateV2><xades:Cert><xades:CertDigest>"
        + #"<ds:DigestMethod Algorithm="\#(AsicVerification.XmlDigestMethod.sha256.uri)"/>"#
        + "<ds:DigestValue>\(Self.digest(signer.certificate))</ds:DigestValue>"
        + "</xades:CertDigest></xades:Cert></xades:SigningCertificateV2>"
        + "</xades:SignedSignatureProperties></xades:SignedProperties>"
      let object =
        #"<ds:Object><xades:QualifyingProperties xmlns:xades="\#(XadesSignature.namespaceXades)" "#
        + "Target=\"#\(Self.signatureId)\">" + properties
        + "</xades:QualifyingProperties></ds:Object>"
      let propertiesDigest = Self.digest(
        try Self.canonical(Self.inSignature(object), identifier: Self.propertiesId))
      let signedInfo = Self.signedInfo(
        method: Self.signatureMethod(signer.kind), listDigest: listDigest,
        propertiesDigest: propertiesDigest)
      let signedInfoDocument = try XmlDocument(Data(Self.inSignature(signedInfo).utf8))
      let signedInfoElement = try #require(signedInfoDocument.root.children.first)
      let canonicalSignedInfo = try #require(
        XmlCanonicalizer.canonicalize(signedInfoElement, method: .exclusive, omitting: nil))
      let value = try Self.sign(canonicalSignedInfo, with: signer).base64EncodedString()
      let signature =
        #"<ds:Signature xmlns:ds="\#(XadesSignature.namespaceDsig)" Id="\#(Self.signatureId)">"#
        + signedInfo + "<ds:SignatureValue>\(value)</ds:SignatureValue>"
        + "<ds:KeyInfo><ds:X509Data><ds:X509Certificate>"
        + signer.certificate.base64EncodedString()
        + "</ds:X509Certificate></ds:X509Data></ds:KeyInfo>" + object + "</ds:Signature>"
      return Data(Self.inserting(signature, into: unsigned).utf8)
    }

    /// `signature` placed before the list's end tag.
    internal static func inserting(_ signature: String, into unsigned: String) -> String {
      let close = "</TrustServiceStatusList>"
      guard let range = unsigned.range(of: close, options: .backwards) else { return unsigned }
      return unsigned.replacingCharacters(in: range, with: signature + close)
    }

    /// `inner` inside a `ds:Signature` that declares the prefix.
    private static func inSignature(_ inner: String) -> String {
      #"<ds:Signature xmlns:ds="\#(XadesSignature.namespaceDsig)">\#(inner)</ds:Signature>"#
    }

    /// The `ds:SignedInfo` with the two references annex B.1 asks for.
    private static func signedInfo(
      method: String,
      listDigest: String,
      propertiesDigest: String
    ) -> String {
      let sha256 = AsicVerification.XmlDigestMethod.sha256.uri
      let exclusive = XadesSignature.canonicalizationExclusive
      return "<ds:SignedInfo>"
        + #"<ds:CanonicalizationMethod Algorithm="\#(exclusive)"/>"#
        + #"<ds:SignatureMethod Algorithm="\#(method)"/>"#
        + #"<ds:Reference Id="ref-enveloped-signature" URI=""><ds:Transforms>"#
        + #"<ds:Transform Algorithm="\#(TrustedListSignature.envelopedSignatureTransform)"/>"#
        + #"<ds:Transform Algorithm="\#(exclusive)"/></ds:Transforms>"#
        + #"<ds:DigestMethod Algorithm="\#(sha256)"/>"#
        + "<ds:DigestValue>\(listDigest)</ds:DigestValue></ds:Reference>"
        + #"<ds:Reference Type="\#(XadesSignature.signedPropertiesType)" "#
        + "URI=\"#\(Self.propertiesId)\"><ds:Transforms>"
        + #"<ds:Transform Algorithm="\#(exclusive)"/></ds:Transforms>"#
        + #"<ds:DigestMethod Algorithm="\#(sha256)"/>"#
        + "<ds:DigestValue>\(propertiesDigest)</ds:DigestValue></ds:Reference>"
        + "</ds:SignedInfo>"
    }

    /// The `ds:SignatureMethod` of `kind` (RFC 6931).
    private static func signatureMethod(
      _ kind: CertificateRevocationListFixtures.SignatureKind
    ) -> String {
      switch kind {
      case .ecdsaSha256:
        "http://www.w3.org/2001/04/xmldsig-more#ecdsa-sha256"

      case .rsaSha256:
        "http://www.w3.org/2001/04/xmldsig-more#rsa-sha256"

      case .ecdsaSha384, .ecdsaSha512, .rsaSha384, .rsaSha512:
        ""
      }
    }

    /// `message` signed by `signer` in the XML form: PKCS #1 v1.5 for
    /// RSA, raw `r || s` for ECDSA.
    private static func sign(_ message: Data, with signer: Operator) throws -> Data {
      let algorithm: SecKeyAlgorithm =
        signer.kind == .rsaSha256
        ? .rsaSignatureMessagePKCS1v15SHA256 : .ecdsaSignatureMessageX962SHA256
      var error: Unmanaged<CFError>?
      let signature = try #require(
        SecKeyCreateSignature(signer.key, algorithm, message as CFData, &error) as Data?)
      guard signer.kind != .rsaSha256 else { return signature }
      return try Self.rawConcatenation(ofDer: signature)
    }

    /// The raw `r || s` of an X9.62 DER signature, each half padded to
    /// the P-256 width.
    private static func rawConcatenation(ofDer der: Data) throws -> Data {
      var outer = DerReader(der)
      guard let sequence = outer.next() else {
        throw CertificateRevocationListFixtures.FixtureFailure.signatureCreation
      }
      var reader = DerReader(der, within: sequence)
      guard let first = reader.next(), let second = reader.next() else {
        throw CertificateRevocationListFixtures.FixtureFailure.signatureCreation
      }
      func padded(_ element: DerReader.Element) -> Data {
        let magnitude = reader.contentData(of: element).drop { byte in byte == 0 }
        return Data(repeating: 0, count: Self.p256HalfWidth - magnitude.count) + magnitude
      }
      return padded(first) + padded(second)
    }
  }

#endif
