// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CryptoKit
import Foundation
import Security

/// Offline verification for ASiC-E / BDOC containers and embedded XAdES signatures.
public enum AsicVerification {
  /// One parsed reference inside ds:SignedInfo.
  internal struct ParsedReference: Sendable {
    internal let identifier: String?
    internal let uri: String
    internal let type: String?
    /// The `Algorithm` of each `ds:Transform`, in document order.
    internal let transforms: [String]
    internal let digestMethod: XmlDigestMethod
    internal let digestValue: Data
  }

  /// A `ds:DigestMethod` this verifier computes (RFC 6931 section 2.1).
  internal enum XmlDigestMethod: Sendable {
    case sha256
    case sha384
    case sha512

    /// SHA-256 (RFC 6931 section 2.1.2).
    private static let sha256Uri = "http://www.w3.org/2001/04/xmlenc#sha256"

    /// SHA-512 (RFC 6931 section 2.1.3).
    private static let sha512Uri = "http://www.w3.org/2001/04/xmlenc#sha512"

    /// The Algorithm URI.
    internal var uri: String {
      switch self {
      case .sha256:
        Self.sha256Uri

      case .sha384:
        XadesSignature.digestMethodSha384

      case .sha512:
        Self.sha512Uri
      }
    }

    /// The method an Algorithm URI names, nil for any other.
    internal init?(uri: String) {
      switch uri {
      case Self.sha256Uri:
        self = .sha256

      case XadesSignature.digestMethodSha384:
        self = .sha384

      case Self.sha512Uri:
        self = .sha512

      default:
        return nil
      }
    }

    /// The digest of `data`.
    internal func hash(_ data: Data) -> Data {
      switch self {
      case .sha256:
        Data(SHA256.hash(data: data))

      case .sha384:
        Data(SHA384.hash(data: data))

      case .sha512:
        Data(SHA512.hash(data: data))
      }
    }
  }

  /// All extracted fields from one ds:Signature element.
  internal struct ParsedSignature: Sendable {
    internal var signatureMethod: String?
    internal var canonicalizationMethod: String?
    /// Every `ds:Reference` in `ds:SignedInfo`, incomplete when one
    /// lacked its URI, digest method or digest value.
    internal var references = Collected<ParsedReference>.complete([])
    internal var signedInfoRawXml: String?
    internal var signatureValueId: String?
    internal var signatureValueBytes: Data?
    internal var signatureValueRawXml: String?
    /// The first `ds:X509Certificate` in the signature's `ds:KeyInfo`.
    internal var signerCertificateDer: Data?
    /// Every `ds:X509Certificate` in the signature's `ds:KeyInfo`, in
    /// document order.
    internal var keyInfoCertificates: [Data] = []
    internal var signedPropertiesId: String?
    internal var signedPropertiesRawXml: String?
    /// Tokens from `xades:SignatureTimeStamp` elements only.
    internal var signatureTimestampTokens: [Data] = []
    /// `xades:EncapsulatedX509Certificate` values from the signature's
    /// `CertificateValues` (EN 319 132-1 clause 5.4.1), including those
    /// in a XAdES 1.4.1 `TimeStampValidationData`.
    internal var certificateValues: [Data] = []
    /// `xades:EncapsulatedOCSPValue` values from its `RevocationValues`
    /// (EN 319 132-1 clause 5.4.2), likewise.
    internal var ocspValues: [Data] = []
    /// `xades:EncapsulatedCRLValue` values from its `RevocationValues`,
    /// likewise.
    internal var crlValues: [Data] = []
    /// Whether this `ds:Signature` sits inside another one, as a
    /// `xades:CounterSignature` does (EN 319 132-1 clause 5.2.7).
    internal var isCounterSignature = false
    /// Each `xades:Cert` of the signing-certificate property, in
    /// document order (EN 319 132-1 clause 5.2.2), incomplete when one
    /// lacked its digest method, a decodable digest value, or a
    /// readable issuer and serial.
    internal var signingCertificates = Collected<SigningCertificateReference>.complete([])
  }

  /// Values collected from repeated elements: all of them, or the fact
  /// that one could not be read.
  internal enum Collected<Value: Sendable>: Sendable {
    /// Every value, in document order.
    case complete([Value])

    /// At least one occurrence could not be read.
    case incomplete

    /// At least one occurrence names an algorithm this verifier does
    /// not know.
    case unsupported

    /// Adds one read value; an incomplete collection stays incomplete.
    internal mutating func append(_ value: Value) {
      guard case .complete(let values) = self else { return }
      self = .complete(values + [value])
    }

    /// Records an occurrence that could not be read; an unsupported
    /// collection stays unsupported.
    internal mutating func markIncomplete() {
      guard case .complete = self else { return }
      self = .incomplete
    }

    /// Records an occurrence naming an unknown algorithm.
    internal mutating func markUnsupported() {
      self = .unsupported
    }
  }

  /// The issuer and serial a `xades:Cert` states.
  internal enum StatedIssuerSerial: Sendable {
    /// `xades:IssuerSerialV2`: the DER IssuerSerial of RFC 5035.
    case der(Data)

    /// `xades:IssuerSerial`: the issuer name as text and the serial in
    /// decimal.
    case text(issuerName: String, serialNumber: String)
  }

  /// The element a signing-certificate reference was read from.
  internal enum SigningCertificateProperty: Sendable {
    /// `xades:SigningCertificate`.
    case versionOne

    /// `xades:SigningCertificateV2`.
    case versionTwo
  }

  /// One certificate a signing-certificate property names.
  internal struct SigningCertificateReference: Sendable {
    /// The property it was read from.
    internal let property: SigningCertificateProperty

    /// The digest method of its CertDigest.
    internal let method: XmlDigestMethod

    /// The certificate digest.
    internal let value: Data

    /// The issuer and serial, when the Cert states them.
    internal let issuerSerial: StatedIssuerSerial?
  }

  /// Prefix of a same-document reference URI, a fragment identifier
  /// (W3C XML-Signature 1.1 section 4.4.3.2).
  internal static let sameDocumentUriPrefix = "#"

  /// Whether the data is a ZIP archive this verifier reads as an
  /// ASiC-E or BDOC container.
  public static func isAsicContainer(_ data: Data) -> Bool {
    guard ZipReader.hasZipSignature(data) else { return false }
    return (try? Self.containerEntries(data)) != nil
  }

  /// Verifies an ASiC-E or BDOC container, returning a complete DocumentReport.
  public static func verify(
    container: Data,
    anchors: TrustAnchors = .pinned,
    now: Date = Date()
  ) throws -> DocumentVerification.DocumentReport {
    let entries = try Self.containerEntries(container)

    let signatureFiles =
      entries.keys
      .filter { key in
        key.hasPrefix("META-INF/") && key.hasSuffix(".xml")
          && (key.contains("signature") || key.contains("signatures"))
      }
      .sorted()

    guard !signatureFiles.isEmpty else {
      throw DocumentVerification.Failure.noSignatures
    }

    let carriedFileNames = Set(
      entries.keys.filter { name in
        name != AsicContainer.mimetypeEntryName && !name.hasPrefix("META-INF/")
      }
    )

    return DocumentVerification.DocumentReport(
      signatures: signatureEntries(
        signatureFiles: signatureFiles,
        entries: entries,
        carriedFileNames: carriedFileNames,
        anchors: anchors,
        now: now
      ),
      documentTimestamps: []
    )
  }

  /// Recomputes every reference in `ds:SignedInfo`
  /// (W3C XML-Signature 1.1 section 3.2.1).
  ///
  /// Fails closed: a reference this verifier cannot recompute counts
  /// as a mismatch, never as a match. A data object reference must
  /// name a carried file and declare no transform; the one
  /// same-document reference must cover the signature's own
  /// `xades:SignedProperties` (EN 319 132-1 clause 4.4.2). Every file
  /// outside `META-INF/` must be referenced (EN 319 162-1
  /// clause 4.4.3.2).
  internal static func checkDocumentIntegrity(
    parsed: ParsedSignature,
    entries: [String: Data],
    carriedFileNames: Set<String>
  ) -> (documentIntact: Bool, coversWholeDocument: Bool) {
    var referencedFiles: Set<String> = []
    var allDigestsMatch = false
    var references: [ParsedReference] = []
    if case .complete(let read) = parsed.references {
      allDigestsMatch = true
      references = read
    }
    var signedPropertiesCovered = false

    for ref in references {
      if ref.uri.hasPrefix(sameDocumentUriPrefix) || ref.type == XadesSignature.signedPropertiesType
      {
        if !signedPropertiesCovered, isSignedPropertiesValid(parsed: parsed, ref: ref) {
          signedPropertiesCovered = true
        } else {
          allDigestsMatch = false
        }
        continue
      }

      let entryName = ref.uri.removingPercentEncoding ?? ref.uri
      referencedFiles.insert(entryName)

      guard ref.transforms.isEmpty,
        let fileContent = entries[entryName],
        ref.digestMethod.hash(fileContent) == ref.digestValue
      else {
        allDigestsMatch = false
        continue
      }
    }

    let allCarriedFilesCovered =
      carriedFileNames.isSubset(of: referencedFiles) && !carriedFileNames.isEmpty
    let documentIntact = allDigestsMatch && signedPropertiesCovered && allCarriedFilesCovered
    return (documentIntact, allCarriedFilesCovered && documentIntact)
  }

  /// Whether `ref` covers this signature's `xades:SignedProperties`
  /// and its digest matches.
  ///
  /// The reference must carry the SignedProperties `Type`, name the
  /// element's `Id`, and declare exclusive canonicalisation as its
  /// one transform, the form `XadesSignature` writes. The element is
  /// digested as it stands in the document, which equals its
  /// exclusive canonical form only when it was written in that form;
  /// any other spelling digests differently and fails. A missing
  /// element or an unsupported digest method fails too.
  private static func isSignedPropertiesValid(
    parsed: ParsedSignature,
    ref: ParsedReference
  ) -> Bool {
    guard ref.type == XadesSignature.signedPropertiesType,
      ref.transforms == [XadesSignature.canonicalizationExclusive],
      let propertiesId = parsed.signedPropertiesId,
      ref.uri == sameDocumentUriPrefix + propertiesId,
      let propertiesRaw = parsed.signedPropertiesRawXml,
      ref.digestMethod.hash(Data(propertiesRaw.utf8)) == ref.digestValue
    else {
      return false
    }
    return true
  }
}
