// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// SAX parser for XAdES signature elements within META-INF signature files.
///
/// Each element is read by its local name and, where the same local
/// name occurs in more than one place, by its enclosing element: a
/// `ds:Reference` counts only inside `ds:SignedInfo`, and an
/// `EncapsulatedTimeStamp` counts only inside a `SignatureTimeStamp`.
internal final class XadesXmlParser: NSObject, XMLParserDelegate {
  /// Local names of the XML-DSig and XAdES elements read here.
  private enum Element {
    static let signature = "Signature"
    static let signedInfo = "SignedInfo"
    static let canonicalizationMethod = "CanonicalizationMethod"
    static let signatureMethod = "SignatureMethod"
    static let reference = "Reference"
    static let transforms = "Transforms"
    static let transform = "Transform"
    static let digestMethod = "DigestMethod"
    static let digestValue = "DigestValue"
    static let signatureValue = "SignatureValue"
    static let keyInfo = "KeyInfo"
    static let x509Certificate = "X509Certificate"
    static let qualifyingProperties = "QualifyingProperties"
    static let signedProperties = "SignedProperties"
    static let unsignedSignatureProperties = "UnsignedSignatureProperties"
    static let signatureTimeStamp = "SignatureTimeStamp"
    static let encapsulatedTimeStamp = "EncapsulatedTimeStamp"
  }

  /// Attribute names read from those elements.
  private enum Attribute {
    static let algorithm = "Algorithm"
    static let identifier = "Id"
    static let uri = "URI"
    static let type = "Type"
  }

  private let xmlString: String
  private var signatures: [AsicVerification.ParsedSignature] = []
  private var currentSignature: AsicVerification.ParsedSignature?

  private var elementStack: [String] = []
  private var currentCharacters = ""

  private var currentRefIdentifier: String?
  private var currentRefUri: String?
  private var currentRefType: String?
  private var currentRefTransforms: [String] = []
  private var currentRefDigestMethod: String?
  private var currentRefDigestValue: Data?

  /// The element enclosing the one being handled, which is the top
  /// of the stack.
  private var parent: String? { elementStack.dropLast().last }

  /// The element enclosing `parent`.
  private var grandparent: String? { elementStack.dropLast().dropLast().last }

  internal init(xmlString: String) {
    self.xmlString = xmlString
    super.init()
  }

  internal func parse(data: Data) -> [AsicVerification.ParsedSignature] {
    let parser = XMLParser(data: data)
    parser.delegate = self
    parser.parse()
    return signatures
  }

  internal func parser(
    _: XMLParser,
    didStartElement elementName: String,
    namespaceURI _: String?,
    qualifiedName _: String?,
    attributes attributeDict: [String: String]
  ) {
    let localName = elementName.components(separatedBy: ":").last ?? elementName
    elementStack.append(localName)
    currentCharacters = ""

    handleStartElement(localName: localName, elementName: elementName, attributeDict: attributeDict)
  }

  private func handleStartElement(
    localName: String,
    elementName: String,
    attributeDict: [String: String]
  ) {
    switch localName {
    case Element.signature:
      currentSignature = AsicVerification.ParsedSignature()

    case Element.signedInfo:
      currentSignature?.signedInfoRawXml = extractElementSlice(tag: elementName, in: xmlString)

    case Element.canonicalizationMethod where parent == Element.signedInfo:
      currentSignature?.canonicalizationMethod = attributeDict[Attribute.algorithm]

    case Element.signatureMethod where parent == Element.signedInfo:
      currentSignature?.signatureMethod = attributeDict[Attribute.algorithm]

    case Element.reference where parent == Element.signedInfo:
      currentRefIdentifier = attributeDict[Attribute.identifier]
      currentRefUri = attributeDict[Attribute.uri]
      currentRefType = attributeDict[Attribute.type]
      currentRefTransforms = []
      currentRefDigestMethod = nil
      currentRefDigestValue = nil

    case Element.transform
    where parent == Element.transforms && grandparent == Element.reference:
      // An absent Algorithm is kept as an empty name, so the reference
      // still carries a transform the verifier cannot apply.
      currentRefTransforms.append(attributeDict[Attribute.algorithm] ?? "")

    case Element.digestMethod where parent == Element.reference:
      currentRefDigestMethod = attributeDict[Attribute.algorithm]

    case Element.signatureValue:
      currentSignature?.signatureValueId = attributeDict[Attribute.identifier]
      currentSignature?.signatureValueRawXml = extractElementSlice(tag: elementName, in: xmlString)

    case Element.signedProperties where parent == Element.qualifyingProperties:
      currentSignature?.signedPropertiesId = attributeDict[Attribute.identifier]
      currentSignature?.signedPropertiesRawXml = extractElementSlice(
        tag: elementName, in: xmlString)

    default:
      break
    }
  }

  internal func parser(_: XMLParser, foundCharacters string: String) {
    currentCharacters += string
  }

  internal func parser(
    _: XMLParser,
    didEndElement elementName: String,
    namespaceURI _: String?,
    qualifiedName _: String?
  ) {
    let localName = elementName.components(separatedBy: ":").last ?? elementName
    let trimmed = currentCharacters.trimmingCharacters(in: .whitespacesAndNewlines)

    handleEndElement(localName: localName, trimmed: trimmed)

    if !elementStack.isEmpty {
      elementStack.removeLast()
    }
    currentCharacters = ""
  }

  private func handleEndElement(localName: String, trimmed: String) {
    switch localName {
    case Element.digestValue where parent == Element.reference:
      currentRefDigestValue = Data(base64Encoded: trimmed)

    case Element.reference where parent == Element.signedInfo:
      appendCurrentReference()

    case Element.signatureValue:
      currentSignature?.signatureValueBytes = Data(base64Encoded: trimmed)

    case Element.x509Certificate:
      if currentSignature?.signerCertificateDer == nil, elementStack.contains(Element.keyInfo) {
        currentSignature?.signerCertificateDer = Data(base64Encoded: trimmed)
      }

    // Only a SignatureTimeStamp time-stamps ds:SignatureValue
    // (EN 319 132-1 clause 5.3). Archive time-stamps (clause 5.5.2)
    // and data object time-stamps (clause 5.2.8) imprint other input
    // and are not read.
    case Element.encapsulatedTimeStamp
    where parent == Element.signatureTimeStamp
      && grandparent == Element.unsignedSignatureProperties:
      if let token = Data(base64Encoded: trimmed) {
        currentSignature?.signatureTimestampTokens.append(token)
      }

    case Element.signature:
      if let finished = currentSignature {
        signatures.append(finished)
      }
      currentSignature = nil

    default:
      break
    }
  }

  /// Adds the reference just closed, or marks the signature as
  /// carrying one that cannot be checked.
  private func appendCurrentReference() {
    guard let uri = currentRefUri,
      let digestMethod = currentRefDigestMethod,
      let digestValue = currentRefDigestValue
    else {
      currentSignature?.allReferencesRead = false
      return
    }
    currentSignature?.references.append(
      AsicVerification.ParsedReference(
        identifier: currentRefIdentifier,
        uri: uri,
        type: currentRefType,
        transforms: currentRefTransforms,
        digestMethod: digestMethod,
        digestValue: digestValue
      )
    )
  }

  private func extractElementSlice(tag: String, in xml: String) -> String? {
    let startOpen = "<\(tag)"
    guard let startRange = xml.range(of: startOpen) else { return nil }
    let endTag = "</\(tag)>"
    guard let endRange = xml.range(of: endTag, range: startRange.lowerBound..<xml.endIndex) else {
      return nil
    }
    return String(xml[startRange.lowerBound..<endRange.upperBound])
  }
}
