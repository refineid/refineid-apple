// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CryptoKit
import Foundation

/// Offline verification for ASiC-E / BDOC containers and embedded XAdES signatures.
public enum AsicVerification {
  /// One parsed reference inside `ds:SignedInfo`.
  internal struct ParsedReference: Sendable {
    internal let identifier: String?
    internal let uri: String
    internal let type: String?
    /// The `Algorithm` of each `ds:Transform`, in document order.
    internal let transforms: [String]
    /// The `ds:Transform` elements, in document order.
    internal let transformElements: [XmlElement]
    internal let digestMethod: XmlDigestMethod
    internal let digestValue: Data
  }

  /// One `xades:EncapsulatedTimeStamp` inside `xades:SignatureTimeStamp` and its canonical input.
  internal struct ParsedSignatureTimestamp: Sendable {
    internal let token: Data
    internal let imprintInput: Data?
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

    /// Expected digest byte count for this algorithm.
    internal var byteCount: Int {
      switch self {
      case .sha256:
        SHA256.byteCount

      case .sha384:
        SHA384.byteCount

      case .sha512:
        SHA512.byteCount
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

  /// All extracted fields from one `ds:Signature` element.
  internal struct ParsedSignature: Sendable {
    internal var signatureElement: XmlElement?
    internal var signedInfoElement: XmlElement?
    internal var signatureValueElement: XmlElement?
    internal var signedPropertiesElement: XmlElement?
    internal var signedInfoCanonicalization: XmlCanonicalization?
    internal var parsedSignatureMethod: XmlSignatureMethod?
    internal var hasStructuralError = false
    internal var signatureMethod: String?
    internal var canonicalizationMethod: String?
    /// Every `ds:Reference` in `ds:SignedInfo`, incomplete when one lacked required fields.
    internal var references = Collected<ParsedReference>.complete([])
    internal var signedInfoRawXml: String?
    internal var signatureValueId: String?
    internal var signatureValueBytes: Data?
    internal var signatureValueRawXml: String?
    /// The first `ds:X509Certificate` in the signature's `ds:KeyInfo`.
    internal var signerCertificateDer: Data?
    /// Every `ds:X509Certificate` in the signature's `ds:KeyInfo`, in document order.
    internal var keyInfoCertificates: [Data] = []
    internal var signedPropertiesId: String?
    internal var signedPropertiesRawXml: String?
    /// Parsed `xades:SignatureTimeStamp` tokens and their canonical `ds:SignatureValue` inputs.
    internal var signatureTimestamps: [ParsedSignatureTimestamp] = []
    internal var certificateValues: [Data] = []
    internal var ocspValues: [Data] = []
    internal var crlValues: [Data] = []
    internal var isCounterSignature = false
    internal var signingCertificates = Collected<SigningCertificateReference>.complete([])

    /// Tokens from `xades:SignatureTimeStamp` elements only.
    internal var signatureTimestampTokens: [Data] {
      signatureTimestamps.map(\.token)
    }
  }

  /// Values collected from repeated elements: all of them, or the fact
  /// that one could not be read.
  internal enum Collected<Value: Sendable>: Sendable {
    /// Every value, in document order.
    case complete([Value])

    /// At least one occurrence could not be read.
    case incomplete

    /// At least one occurrence names an algorithm this verifier does not know.
    case unsupported

    /// Adds one read value; an incomplete collection stays incomplete.
    internal mutating func append(_ value: Value) {
      guard case .complete(let values) = self else { return }
      self = .complete(values + [value])
    }

    /// Records an occurrence that could not be read; an unsupported collection stays unsupported.
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

    /// `xades:IssuerSerial`: the issuer name as text and the serial in decimal.
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
    internal let property: SigningCertificateProperty
    internal let method: XmlDigestMethod
    internal let value: Data
    internal let issuerSerial: StatedIssuerSerial?
  }

  /// Prefix of a same-document reference URI, a fragment identifier (W3C XML-Signature 1.1 §4.4.3.2).
  internal static let sameDocumentUriPrefix = "#"

  /// Whether the data opens as a ZIP archive, a signature container or not.
  public static func isZipArchive(_ data: Data) -> Bool {
    ZipReader.hasZipSignature(data)
  }

  /// Whether the data is a ZIP archive this verifier reads as an ASiC-E or BDOC container.
  public static func isAsicContainer(_ data: Data) -> Bool {
    guard ZipReader.hasZipSignature(data) else { return false }
    return (try? Self.containerEntries(data)) != nil
  }

  /// Verifies an ASiC-E or BDOC container, returning a complete DocumentReport.
  public static func verify(
    container: Data,
    anchors: TrustAnchors,
    now: Date = Date()
  ) throws -> DocumentVerification.DocumentReport {
    let entries = try Self.containerEntries(container)

    let xadesSignatureFiles = entries.keys.filter(Self.isXadesSignatureEntry).sorted()
    let unsupportedEntries =
      entries.keys
      .filter { name in
        Self.isCadesSignatureEntry(name) || Self.isTimestampAssertionEntry(name)
      }
      .sorted()
      .map { _ in DocumentVerification.SignatureEntry.unsupported }

    guard !xadesSignatureFiles.isEmpty || !unsupportedEntries.isEmpty else {
      throw DocumentVerification.Failure.noSignatures
    }

    let carriedFileNames = Set(
      entries.keys.filter { name in
        name != AsicContainer.mimetypeEntryName && !name.hasPrefix(Self.metaInfPrefix)
      }
    )

    let xadesEntries = Self.signatureEntries(
      signatureFiles: xadesSignatureFiles,
      judgement: ContainerJudgement(
        entries: entries, carriedFileNames: carriedFileNames, anchors: anchors, now: now)
    )

    return DocumentVerification.DocumentReport(
      signatures: xadesEntries + unsupportedEntries,
      documentTimestamps: []
    )
  }

  /// Recomputes every reference in `ds:SignedInfo` (W3C XML-Signature 1.1 section 3.2.1).
  internal static func checkDocumentIntegrity(
    parsed: ParsedSignature,
    entries: [String: Data],
    carriedFileNames: Set<String>
  ) -> (documentIntact: Bool, coversWholeDocument: Bool) {
    guard !parsed.hasStructuralError, case .complete(let references) = parsed.references else {
      return (false, false)
    }
    var referencedFiles: Set<String> = []
    var allDigestsMatch = !references.isEmpty
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

      guard !ref.uri.isEmpty, ref.transformElements.isEmpty,
        let matched = Self.carriedEntry(namedByUri: ref.uri, in: entries)
      else {
        allDigestsMatch = false
        continue
      }
      referencedFiles.insert(matched.name)
      if ref.digestMethod.hash(matched.content) != ref.digestValue {
        allDigestsMatch = false
      }
    }

    let allCarriedFilesCovered =
      carriedFileNames.isSubset(of: referencedFiles) && !carriedFileNames.isEmpty
    let documentIntact = allDigestsMatch && signedPropertiesCovered && allCarriedFilesCovered
    return (documentIntact, allCarriedFilesCovered && documentIntact)
  }

  /// Resolves a relative reference URI against carried container entries.
  private static func carriedEntry(
    namedByUri uri: String,
    in entries: [String: Data]
  ) -> (name: String, content: Data)? {
    if uri != AsicContainer.mimetypeEntryName, !uri.hasPrefix(Self.metaInfPrefix),
      let content = entries[uri]
    {
      return (uri, content)
    }
    guard let decoded = uri.removingPercentEncoding,
      decoded != AsicContainer.mimetypeEntryName,
      !decoded.hasPrefix(Self.metaInfPrefix),
      let content = entries[decoded]
    else {
      return nil
    }
    return (decoded, content)
  }

  /// Whether `ref` covers this signature's `xades:SignedProperties` under XML canonicalisation.
  private static func isSignedPropertiesValid(
    parsed: ParsedSignature,
    ref: ParsedReference
  ) -> Bool {
    guard
      ref.type == XadesSignature.signedPropertiesType,
      let propertiesElement = parsed.signedPropertiesElement,
      let propertiesId = parsed.signedPropertiesId,
      ref.uri == sameDocumentUriPrefix + propertiesId,
      propertiesElement.document.element(withId: propertiesId) == propertiesElement,
      let canonicalization = Self.signedPropertiesCanonicalization(ref.transformElements),
      let canonicalBytes = XmlCanonicalizer.canonicalize(
        propertiesElement, method: canonicalization, omitting: nil)
    else {
      return false
    }
    return ref.digestMethod.hash(canonicalBytes) == ref.digestValue
  }

  /// Canonicalisation for a bare-name `#id` reference: comments omitted per XML-DSig 1.1 §4.4.3.3.
  private static func signedPropertiesCanonicalization(
    _ transforms: [XmlElement]
  ) -> XmlCanonicalization? {
    guard let only = transforms.first else {
      return .inclusive
    }
    guard transforms.count == 1, let method = XmlCanonicalization(method: only) else {
      return nil
    }
    return XmlCanonicalization(algorithm: method.algorithm, comments: .omitted)
  }
}
