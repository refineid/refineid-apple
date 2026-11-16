// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// Strict namespace-aware XAdES signature parser backed by `XmlDocument`.
///
/// Matches every XML-DSig and XAdES element by `(namespaceURI, localName)`
/// and enforces XML-DSig / XAdES schema cardinality on `ds:Signature`,
/// `ds:SignedInfo`, `ds:Reference`, and `xades:QualifyingProperties`.
internal final class XadesXmlParser {
  /// Attribute names read from XML-DSig and XAdES elements.
  internal enum Attribute {
    internal static let algorithm = "Algorithm"
    internal static let identifier = "Id"
    internal static let target = "Target"
    internal static let type = "Type"
    internal static let uri = "URI"
  }

  /// Local names of the XML-DSig and XAdES elements the parser reads.
  internal enum Element {
    internal static let signature = "Signature"
    internal static let signedInfo = "SignedInfo"
    internal static let canonicalizationMethod = "CanonicalizationMethod"
    internal static let signatureMethod = "SignatureMethod"
    internal static let reference = "Reference"
    internal static let transforms = "Transforms"
    internal static let transform = "Transform"
    internal static let digestMethod = "DigestMethod"
    internal static let digestValue = "DigestValue"
    internal static let signatureValue = "SignatureValue"
    internal static let keyInfo = "KeyInfo"
    internal static let x509Data = "X509Data"
    internal static let x509Certificate = "X509Certificate"
    internal static let object = "Object"
    internal static let qualifyingProperties = "QualifyingProperties"
    internal static let signedProperties = "SignedProperties"
    internal static let signedDataObjectProperties = "SignedDataObjectProperties"
    internal static let unsignedProperties = "UnsignedProperties"
    internal static let unsignedSignatureProperties = "UnsignedSignatureProperties"
    internal static let unsignedDataObjectProperties = "UnsignedDataObjectProperties"
    internal static let signatureTimeStamp = "SignatureTimeStamp"
    internal static let encapsulatedTimeStamp = "EncapsulatedTimeStamp"
    internal static let certificateValues = "CertificateValues"
    internal static let encapsulatedX509Certificate = "EncapsulatedX509Certificate"
    internal static let revocationValues = "RevocationValues"
    internal static let crlValues = "CRLValues"
    internal static let encapsulatedCrlValue = "EncapsulatedCRLValue"
    internal static let ocspValues = "OCSPValues"
    internal static let encapsulatedOcspValue = "EncapsulatedOCSPValue"
    internal static let timeStampValidationData = "TimeStampValidationData"
    internal static let signedSignatureProperties = "SignedSignatureProperties"
    internal static let signingTime = "SigningTime"
    internal static let signingCertificate = "SigningCertificate"
    internal static let signingCertificateV2 = "SigningCertificateV2"
    internal static let cert = "Cert"
    internal static let certDigest = "CertDigest"
    internal static let issuerSerialV2 = "IssuerSerialV2"
    internal static let issuerSerial = "IssuerSerial"
    internal static let x509IssuerName = "X509IssuerName"
    internal static let x509SerialNumber = "X509SerialNumber"
  }

  /// Validation material decoded from an unsigned signature property.
  internal struct ValidationMaterial {
    internal var certificates: [Data] = []
    internal var ocspResponses: [Data] = []
    internal var revocationLists: [Data] = []
  }

  /// Sequence stages of `(SignedInfo, SignatureValue, KeyInfo?, Object*)` inside `ds:Signature`.
  private enum SignatureStage {
    case initial
    case afterSignedInfo
    case afterSignatureValue
    case afterKeyInfo
    case inObjects
  }

  /// Validated direct children of one `ds:Signature`.
  private struct SignatureChildren {
    var signedInfo: XmlElement?
    var signatureValue: XmlElement?
    var keyInfo: XmlElement?
    var objects: [XmlElement] = []
    var isValid = true
  }

  /// The XML whitespace characters (XML 1.0 production 3), the only
  /// characters stripped from base64 content before decoding.
  private static let xmlWhitespace: Set<Unicode.Scalar> = [" ", "\t", "\r", "\n"]

  /// Protected local names forbidden outside their single canonical XAdES / XML-DSig slot.
  private static let protectedLocalNames: Set<String> = [
    Element.signedInfo,
    Element.signatureValue,
    Element.qualifyingProperties,
    Element.signedProperties,
    Element.signedSignatureProperties,
  ]

  /// Whether the last `parse(data:)` read the whole document as accepted XML.
  internal private(set) var parsedWholeDocument = false

  /// Base64 content with XML whitespace anywhere in it, decoded strictly; nil for other characters.
  internal static func base64(_ text: String) -> Data? {
    let scalars = text.unicodeScalars.filter { !Self.xmlWhitespace.contains($0) }
    return Data(base64Encoded: String(String.UnicodeScalarView(scalars)))
  }

  /// Text content with surrounding XML whitespace removed.
  internal static func trimmed(_ text: String) -> String {
    var scalars = Substring(text).unicodeScalars
    while let first = scalars.first, Self.xmlWhitespace.contains(first) {
      scalars.removeFirst()
    }
    while let last = scalars.last, Self.xmlWhitespace.contains(last) {
      scalars.removeLast()
    }
    return String(scalars)
  }

  /// Whether the document root is `<ds:Signature>` or `<asic:XAdESSignatures>` holding only `<ds:Signature>` children.
  private static func isAcceptedRoot(_ root: XmlElement) -> Bool {
    if root.matches(XadesSignature.namespaceDsig, Element.signature) {
      return true
    }
    guard root.matches(XadesSignature.namespaceAsic, "XAdESSignatures") else {
      return false
    }
    return root.children.allSatisfy { child in
      child.matches(XadesSignature.namespaceDsig, Element.signature)
    }
  }

  /// Reads one `ds:Signature` element and validates its XML-DSig / XAdES structure.
  private static func parseSignature(
    _ signature: XmlElement,
    source: Data
  ) -> AsicVerification.ParsedSignature {
    var parsed = AsicVerification.ParsedSignature()
    parsed.signatureElement = signature
    parsed.isCounterSignature = Self.hasSignatureAncestor(signature)

    let topLevel = Self.validateSignatureChildren(signature)
    if !topLevel.isValid {
      parsed.hasStructuralError = true
    }
    if let signedInfo = topLevel.signedInfo {
      Self.populateSignedInfo(signedInfo, source: source, into: &parsed)
    } else {
      parsed.hasStructuralError = true
    }
    if let signatureValue = topLevel.signatureValue {
      Self.populateSignatureValue(signatureValue, source: source, into: &parsed)
    } else {
      parsed.hasStructuralError = true
    }
    if let keyInfo = topLevel.keyInfo {
      Self.populateKeyInfo(keyInfo, into: &parsed)
    }
    Self.populateObjects(topLevel.objects, signature: signature, source: source, into: &parsed)
    return parsed
  }

  /// Whether `element` sits inside an enclosing `ds:Signature`.
  private static func hasSignatureAncestor(_ element: XmlElement) -> Bool {
    var cursor = element.parent
    while let current = cursor {
      if current.matches(XadesSignature.namespaceDsig, Element.signature) {
        return true
      }
      cursor = current.parent
    }
    return false
  }

  /// Validates the `(SignedInfo, SignatureValue, KeyInfo?, Object*)` sequence of `ds:Signature`.
  private static func validateSignatureChildren(
    _ signature: XmlElement
  ) -> SignatureChildren {
    var result = SignatureChildren()
    var stage = SignatureStage.initial
    for child in signature.children {
      if child.namespace == XadesSignature.namespaceDsig {
        Self.advanceSignatureStage(for: child, stage: &stage, into: &result)
      } else {
        result.isValid = false
      }
    }
    if result.signedInfo == nil || result.signatureValue == nil {
      result.isValid = false
    }
    return result
  }

  /// Advances `stage` for one `dsig`-namespaced direct child of `ds:Signature`.
  private static func advanceSignatureStage(
    for child: XmlElement,
    stage: inout SignatureStage,
    into result: inout SignatureChildren
  ) {
    switch (child.localName, stage) {
    case (Element.signedInfo, .initial):
      result.signedInfo = child
      stage = .afterSignedInfo

    case (Element.signatureValue, .afterSignedInfo):
      result.signatureValue = child
      stage = .afterSignatureValue

    case (Element.keyInfo, .afterSignatureValue):
      result.keyInfo = child
      stage = .afterKeyInfo

    case (Element.object, .afterSignatureValue),
      (Element.object, .afterKeyInfo),
      (Element.object, .inObjects):
      result.objects.append(child)
      stage = .inObjects

    default:
      result.isValid = false
    }
  }

  /// Checks whether `subtree` (stopping at nested `ds:Signature`s) hides protected local names outside `allowed`.
  internal static func containsShadowedProtectedElement(
    in root: XmlElement,
    allowing allowedIndices: Set<Int>
  ) -> Bool {
    var stack = root.children
    while let element = stack.popLast() {
      if element.matches(XadesSignature.namespaceDsig, Element.signature) {
        continue
      }
      if Self.protectedLocalNames.contains(element.localName),
        !allowedIndices.contains(element.index)
      {
        return true
      }
      stack.append(contentsOf: element.children)
    }
    return false
  }

  /// Slice of UTF-8 source text for `element`.
  internal static func rawSlice(_ element: XmlElement, in source: Data) -> String? {
    String(data: source.subdata(in: element.span), encoding: .utf8)
  }

  /// Parses every `ds:Signature` in `data`, or returns empty when `XmlDocument` refuses `data`.
  internal func parse(data: Data) -> [AsicVerification.ParsedSignature] {
    guard let document = try? XmlDocument(data) else {
      parsedWholeDocument = false
      return []
    }
    parsedWholeDocument = true
    let rootValid = Self.isAcceptedRoot(document.root)
    let signatures = document.allElements().filter { element in
      element.matches(XadesSignature.namespaceDsig, Element.signature)
    }
    return signatures.map { signature in
      var parsed = Self.parseSignature(signature, source: data)
      if !rootValid {
        parsed.hasStructuralError = true
      }
      return parsed
    }
  }
}
