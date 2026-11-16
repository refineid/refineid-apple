// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// Subtree extraction and XAdES cardinality validation for `XadesXmlParser`.
extension XadesXmlParser {
  /// Populates `ds:SignedInfo` fields and validates `(CanonicalizationMethod, SignatureMethod, Reference+)`.
  internal static func populateSignedInfo(
    _ signedInfo: XmlElement,
    source: Data,
    into parsed: inout AsicVerification.ParsedSignature
  ) {
    parsed.signedInfoElement = signedInfo
    parsed.signedInfoRawXml = Self.rawSlice(signedInfo, in: source)
    let dsig = XadesSignature.namespaceDsig
    var iterator = signedInfo.children.makeIterator()
    guard
      let c14nElement = iterator.next(),
      c14nElement.matches(dsig, Element.canonicalizationMethod),
      let sigMethodElement = iterator.next(),
      sigMethodElement.matches(dsig, Element.signatureMethod)
    else {
      parsed.hasStructuralError = true
      for reference in signedInfo.children(dsig, Element.reference) {
        Self.appendReference(reference, into: &parsed)
      }
      return
    }
    let references = Array(iterator)
    guard !references.isEmpty, references.allSatisfy({ $0.matches(dsig, Element.reference) }) else {
      parsed.hasStructuralError = true
      for reference in signedInfo.children(dsig, Element.reference) {
        Self.appendReference(reference, into: &parsed)
      }
      return
    }

    parsed.canonicalizationMethod = c14nElement.attribute(Attribute.algorithm)
    parsed.signedInfoCanonicalization = XmlCanonicalization(method: c14nElement)
    parsed.signatureMethod = sigMethodElement.attribute(Attribute.algorithm)
    parsed.parsedSignatureMethod = parsed.signatureMethod.flatMap(XmlSignatureMethod.init(uri:))
    if !sigMethodElement.children.isEmpty {
      parsed.hasStructuralError = true
    }
    for reference in references {
      Self.appendReference(reference, into: &parsed)
    }
  }

  /// Populates `ds:SignatureValue` and checks that it carries no child elements.
  internal static func populateSignatureValue(
    _ signatureValue: XmlElement,
    source: Data,
    into parsed: inout AsicVerification.ParsedSignature
  ) {
    parsed.signatureValueElement = signatureValue
    parsed.signatureValueId = signatureValue.attribute(Attribute.identifier)
    parsed.signatureValueRawXml = Self.rawSlice(signatureValue, in: source)
    parsed.signatureValueBytes = Self.base64(signatureValue.text)
    if !signatureValue.children.isEmpty || parsed.signatureValueBytes == nil {
      parsed.hasStructuralError = true
    }
  }

  /// Populates `ds:KeyInfo` certificates and checks against shadowed protected elements.
  internal static func populateKeyInfo(
    _ keyInfo: XmlElement,
    into parsed: inout AsicVerification.ParsedSignature
  ) {
    if Self.containsShadowedProtectedElement(in: keyInfo, allowing: []) {
      parsed.hasStructuralError = true
    }
    let dsig = XadesSignature.namespaceDsig
    for dataElement in keyInfo.children(dsig, Element.x509Data) {
      for certElement in dataElement.children(dsig, Element.x509Certificate) {
        guard certElement.children.isEmpty, let der = Self.base64(certElement.text) else {
          parsed.hasStructuralError = true
          continue
        }
        parsed.keyInfoCertificates.append(der)
        if parsed.signerCertificateDer == nil {
          parsed.signerCertificateDer = der
        }
      }
    }
  }

  /// Populates `xades:QualifyingProperties` from `objects` and enforces XAdES cardinality.
  internal static func populateObjects(
    _ objects: [XmlElement],
    signature: XmlElement,
    source: Data,
    into parsed: inout AsicVerification.ParsedSignature
  ) {
    let qualifyingList = objects.flatMap { object in
      object.children(XadesSignature.namespaceXades, Element.qualifyingProperties)
    }
    if qualifyingList.count > 1 {
      parsed.hasStructuralError = true
    }
    guard let qualifying = qualifyingList.first else {
      for object in objects where Self.containsShadowedProtectedElement(in: object, allowing: []) {
        parsed.hasStructuralError = true
      }
      return
    }
    guard
      qualifying.parent?.children.count == 1,
      let target = qualifying.attribute(Attribute.target),
      let sigId = signature.attribute(Attribute.identifier),
      !sigId.isEmpty,
      target == AsicVerification.sameDocumentUriPrefix + sigId
    else {
      parsed.hasStructuralError = true
      return
    }

    let signedProps = Self.validateQualifyingChildren(qualifying, into: &parsed)
    var allowed: Set<Int> = [qualifying.index]
    if let signedProps {
      allowed.insert(signedProps.index)
      if let signedSigProps = Self.populateSignedProperties(
        signedProps, source: source, into: &parsed)
      {
        allowed.insert(signedSigProps.index)
      }
    }
    for object in objects where Self.containsShadowedProtectedElement(in: object, allowing: allowed)
    {
      parsed.hasStructuralError = true
    }
    if let unsigned = qualifying.child(XadesSignature.namespaceXades, Element.unsignedProperties) {
      Self.populateUnsignedProperties(unsigned, into: &parsed)
    }
  }

  /// Validates direct children of `xades:QualifyingProperties` (`SignedProperties?`, `UnsignedProperties?`).
  private static func validateQualifyingChildren(
    _ qualifying: XmlElement,
    into parsed: inout AsicVerification.ParsedSignature
  ) -> XmlElement? {
    let xades = XadesSignature.namespaceXades
    var signed: XmlElement?
    var unsigned: XmlElement?
    for child in qualifying.children {
      guard child.namespace == xades else {
        parsed.hasStructuralError = true
        continue
      }
      switch child.localName {
      case Element.signedProperties:
        if signed == nil, unsigned == nil {
          signed = child
        } else {
          parsed.hasStructuralError = true
        }

      case Element.unsignedProperties:
        if unsigned == nil {
          unsigned = child
        } else {
          parsed.hasStructuralError = true
        }

      default:
        parsed.hasStructuralError = true
      }
    }
    return signed
  }

  /// Validates `xades:SignedProperties` and extracts signing-certificate bindings.
  private static func populateSignedProperties(
    _ signedProps: XmlElement,
    source: Data,
    into parsed: inout AsicVerification.ParsedSignature
  ) -> XmlElement? {
    parsed.signedPropertiesElement = signedProps
    parsed.signedPropertiesId = signedProps.attribute(Attribute.identifier)
    parsed.signedPropertiesRawXml = Self.rawSlice(signedProps, in: source)

    let xades = XadesSignature.namespaceXades
    var signedSigProps: XmlElement?
    var seenDataObjectProps = false
    for child in signedProps.children {
      guard child.namespace == xades else {
        parsed.hasStructuralError = true
        continue
      }
      switch child.localName {
      case Element.signedSignatureProperties:
        if signedSigProps == nil, !seenDataObjectProps {
          signedSigProps = child
        } else {
          parsed.hasStructuralError = true
        }

      case Element.signedDataObjectProperties:
        if !seenDataObjectProps {
          seenDataObjectProps = true
        } else {
          parsed.hasStructuralError = true
        }

      default:
        parsed.hasStructuralError = true
      }
    }
    if let signedSigProps {
      Self.populateSignedSignatureProperties(signedSigProps, into: &parsed)
    }
    return signedSigProps
  }

  /// Validates `xades:SignedSignatureProperties` cardinality and extracts `SigningCertificate*`.
  private static func populateSignedSignatureProperties(
    _ signedSigProps: XmlElement,
    into parsed: inout AsicVerification.ParsedSignature
  ) {
    let xades = XadesSignature.namespaceXades
    let signingTimes = signedSigProps.children(xades, Element.signingTime)
    let v2List = signedSigProps.children(xades, Element.signingCertificateV2)
    let v1List = signedSigProps.children(xades, Element.signingCertificate)
    if signingTimes.count > 1 || v2List.count > 1 || v1List.count > 1
      || signedSigProps.children.contains(where: { $0.namespace != xades })
    {
      parsed.hasStructuralError = true
    }
    for versionTwo in v2List {
      Self.appendCertReferences(in: versionTwo, property: .versionTwo, into: &parsed)
    }
    for versionOne in v1List {
      Self.appendCertReferences(in: versionOne, property: .versionOne, into: &parsed)
    }
  }

  /// Validates `xades:UnsignedProperties` and extracts `SignatureTimeStamp`s and validation material.
  private static func populateUnsignedProperties(
    _ unsigned: XmlElement,
    into parsed: inout AsicVerification.ParsedSignature
  ) {
    let xades = XadesSignature.namespaceXades
    let sigPropsList = unsigned.children(xades, Element.unsignedSignatureProperties)
    let objPropsList = unsigned.children(xades, Element.unsignedDataObjectProperties)
    if sigPropsList.count > 1 || objPropsList.count > 1
      || unsigned.children.count != sigPropsList.count + objPropsList.count
    {
      parsed.hasStructuralError = true
    }
    guard let sigProps = sigPropsList.first else { return }
    for property in sigProps.children {
      if property.matches(xades, Element.signatureTimeStamp) {
        Self.appendSignatureTimestamps(from: property, into: &parsed)
      }
      let material = Self.validationMaterial(in: property)
      parsed.certificateValues.append(contentsOf: material.certificates)
      parsed.ocspValues.append(contentsOf: material.ocspResponses)
      parsed.crlValues.append(contentsOf: material.revocationLists)
    }
  }

  /// Extracts certificates, OCSP responses, and CRLs from one unsigned property element.
  internal static func validationMaterial(in property: XmlElement) -> ValidationMaterial {
    let xades = XadesSignature.namespaceXades
    var material = ValidationMaterial()
    if property.matches(XadesSignature.namespaceXades141, Element.timeStampValidationData) {
      for inner in property.children
      where !inner.matches(XadesSignature.namespaceXades141, Element.timeStampValidationData) {
        let nested = Self.validationMaterial(in: inner)
        material.certificates.append(contentsOf: nested.certificates)
        material.ocspResponses.append(contentsOf: nested.ocspResponses)
        material.revocationLists.append(contentsOf: nested.revocationLists)
      }
    } else if property.matches(xades, Element.certificateValues) {
      material.certificates = property.children(xades, Element.encapsulatedX509Certificate)
        .filter(\.children.isEmpty)
        .compactMap { Self.base64($0.text) }
    } else if property.matches(xades, Element.revocationValues) {
      material.revocationLists = property.children(xades, Element.crlValues)
        .flatMap { $0.children(xades, Element.encapsulatedCrlValue) }
        .filter(\.children.isEmpty)
        .compactMap { Self.base64($0.text) }
      material.ocspResponses = property.children(xades, Element.ocspValues)
        .flatMap { $0.children(xades, Element.encapsulatedOcspValue) }
        .filter(\.children.isEmpty)
        .compactMap { Self.base64($0.text) }
    }
    return material
  }
}
