// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// SAX parser for XAdES signature elements within META-INF signature files.
///
/// Each element is read by its local name and its path below the
/// `ds:Signature` that owns it, so a `ds:Reference` counts only inside
/// that signature's `ds:SignedInfo`, and an `EncapsulatedTimeStamp`
/// only inside its own `SignatureTimeStamp`.
///
/// A `ds:Signature` that starts while another is open, as a
/// `xades:CounterSignature` carries one (EN 319 132-1 clause 5.2.7),
/// is collected on its own and marked `isCounterSignature`; nothing
/// inside it reaches the enclosing signature. Signatures are returned
/// in the order their start tags appear in the document, so an outer
/// signature precedes the signatures nested in it.
///
/// The raw text of `ds:SignedInfo`, `ds:SignatureValue` and
/// `xades:SignedProperties` is cut from the document by `XmlElementSpans`,
/// which locates every element by its position among the document's
/// start tags, the same order in which the SAX parser reports them.
/// A document `XmlElementSpans` refuses, among them one carrying a
/// document type declaration, is never handed to `XMLParser`, which
/// also resolves no external entities.
///
/// The state of an element in progress, a reference, a
/// signing-certificate Cert or character data, belongs to the
/// innermost open signature, so a nested signature leaves the
/// enclosing one's partial values untouched.
internal final class XadesXmlParser: NSObject, XMLParserDelegate {
  /// Attribute names read from the elements.
  internal enum Attribute {
    internal static let algorithm = "Algorithm"
    internal static let identifier = "Id"
    internal static let uri = "URI"
    internal static let type = "Type"
  }

  /// One `ds:Reference` being read.
  internal struct PendingReference {
    internal var identifier: String?
    internal var uri: String?
    internal var type: String?
    internal var transforms: [String] = []
    internal var digestMethod: String?
    internal var digestValue: Data?
  }

  /// One signing-certificate `xades:Cert` being read.
  internal struct PendingCertificate {
    internal var digestMethod: String?
    internal var digestValue: Data?
    internal var issuerSerialV2: Data?
    internal var issuerName: String?
    internal var serialNumber: String?
    internal var unreadable = false
  }

  /// One signature being read, with where it starts and its elements
  /// in progress.
  internal struct OpenSignature {
    /// The fields read so far.
    internal var parsed: AsicVerification.ParsedSignature

    /// The element-stack depth of its `ds:Signature` element.
    internal let depth: Int

    /// Its position among the document's elements.
    internal let ordinal: Int

    /// The reference in progress.
    internal var reference = PendingReference()

    /// The signing-certificate Cert in progress.
    internal var certificate = PendingCertificate()

    /// The character data of the element in progress.
    internal var characters = ""
  }

  /// The XML whitespace characters (XML 1.0 production 3), the only
  /// characters stripped from base64 content before decoding.
  private static let xmlWhitespace: Set<Unicode.Scalar> = [" ", "\t", "\r", "\n"]

  /// Whether the last `parse(data:)` read the whole document as
  /// well-formed XML.
  internal private(set) var parsedWholeDocument = false

  private var spans = XmlElementSpans(Data())
  private var finished: [(ordinal: Int, parsed: AsicVerification.ParsedSignature)] = []
  private var openSignatures: [OpenSignature] = []

  private var elementStack: [String] = []
  private var startedElements = 0

  /// The innermost open signature.
  internal var innermost: OpenSignature? { openSignatures.last }

  /// The current element's path below the innermost open signature;
  /// empty outside every signature and on a signature element itself.
  private var pathInSignature: [String] {
    guard let open = openSignatures.last, elementStack.count > open.depth else {
      return []
    }
    return Array(elementStack[open.depth...])
  }

  /// Whether the current element is the innermost open `ds:Signature`.
  private var isAtOpenSignature: Bool {
    guard let open = openSignatures.last else { return false }
    return elementStack.count == open.depth
  }

  /// The local part of a qualified element name.
  private static func localName(of elementName: String) -> String {
    elementName.components(separatedBy: ":").last ?? elementName
  }

  /// Base64 content with XML whitespace anywhere in it, decoded
  /// strictly; nil for any other character.
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

  /// Every signature in `data`, or none when the spans scan refuses it.
  internal func parse(data: Data) -> [AsicVerification.ParsedSignature] {
    spans = XmlElementSpans(data)
    guard spans.isReadable else {
      parsedWholeDocument = false
      return []
    }
    let parser = XMLParser(data: data)
    parser.shouldResolveExternalEntities = false
    parser.delegate = self
    parsedWholeDocument = parser.parse()
    return finished.sorted { $0.ordinal < $1.ordinal }.map(\.parsed)
  }

  internal func parser(
    _: XMLParser,
    didStartElement elementName: String,
    namespaceURI _: String?,
    qualifiedName _: String?,
    attributes attributeDict: [String: String]
  ) {
    let ordinal = startedElements
    startedElements += 1
    let localName = Self.localName(of: elementName)
    if localName == Element.signature {
      var parsed = AsicVerification.ParsedSignature()
      parsed.isCounterSignature = !openSignatures.isEmpty
      openSignatures.append(
        OpenSignature(parsed: parsed, depth: elementStack.count + 1, ordinal: ordinal))
    }
    elementStack.append(localName)
    updateOpen { open in open.characters = "" }

    handleStartElement(
      path: pathInSignature,
      raw: spans.text(ofElement: ordinal, named: elementName),
      attributeDict: attributeDict
    )
  }

  internal func parser(_: XMLParser, foundCharacters string: String) {
    updateOpen { open in open.characters += string }
  }

  internal func parser(
    _: XMLParser,
    didEndElement _: String,
    namespaceURI _: String?,
    qualifiedName _: String?
  ) {
    if isAtOpenSignature, let open = openSignatures.popLast() {
      finished.append((open.ordinal, open.parsed))
    } else if let text = openSignatures.last?.characters {
      handleEndElement(path: pathInSignature, text: text)
    }

    if !elementStack.isEmpty {
      elementStack.removeLast()
    }
    updateOpen { open in open.characters = "" }
  }

  private func handleStartElement(
    path: [String],
    raw: String?,
    attributeDict: [String: String]
  ) {
    switch path {
    case Path.signedInfo:
      update { signature in signature.signedInfoRawXml = raw }

    case Path.canonicalizationMethod:
      update { signature in
        signature.canonicalizationMethod = attributeDict[Attribute.algorithm]
      }

    case Path.signatureMethod:
      update { signature in signature.signatureMethod = attributeDict[Attribute.algorithm] }

    case Path.reference:
      updateOpen { open in
        open.reference = PendingReference(
          identifier: attributeDict[Attribute.identifier],
          uri: attributeDict[Attribute.uri],
          type: attributeDict[Attribute.type]
        )
      }

    case Path.transform:
      // An absent Algorithm is kept as an empty name, so the reference
      // still carries a transform the verifier cannot apply.
      updateOpen { open in
        open.reference.transforms.append(attributeDict[Attribute.algorithm] ?? "")
      }

    case Path.digestMethod:
      updateOpen { open in open.reference.digestMethod = attributeDict[Attribute.algorithm] }

    case Path.signatureValue:
      update { signature in
        signature.signatureValueId = attributeDict[Attribute.identifier]
        signature.signatureValueRawXml = raw
      }

    case Path.signedProperties:
      update { signature in
        signature.signedPropertiesId = attributeDict[Attribute.identifier]
        signature.signedPropertiesRawXml = raw
      }

    default:
      handleCertificateStart(path: path, attributeDict: attributeDict)
    }
  }

  private func handleEndElement(path: [String], text: String) {
    switch path {
    case Path.digestValue:
      updateOpen { open in open.reference.digestValue = Self.base64(text) }

    case Path.reference:
      appendCurrentReference()

    case Path.signatureValue:
      update { signature in signature.signatureValueBytes = Self.base64(text) }

    case Path.keyInfoCertificate:
      guard let certificate = Self.base64(text) else { return }
      update { signature in
        signature.keyInfoCertificates.append(certificate)
        if signature.signerCertificateDer == nil {
          signature.signerCertificateDer = certificate
        }
      }

    // Only a SignatureTimeStamp time-stamps ds:SignatureValue
    // (EN 319 132-1 clause 5.3). Archive time-stamps (clause 5.5.2)
    // and data object time-stamps (clause 5.2.8) imprint other input
    // and are not read.
    case Path.signatureTimestampToken:
      guard let token = Self.base64(text) else { return }
      update { signature in signature.signatureTimestampTokens.append(token) }

    default:
      handleOtherEnd(path: path, text: text)
    }
  }

  /// Applies `change` to the innermost open signature's record.
  internal func updateOpen(_ change: (inout OpenSignature) -> Void) {
    guard !openSignatures.isEmpty else { return }
    change(&openSignatures[openSignatures.count - 1])
  }

  /// Applies `change` to the innermost open signature's fields.
  internal func update(_ change: (inout AsicVerification.ParsedSignature) -> Void) {
    updateOpen { open in change(&open.parsed) }
  }
}
