// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// Reference, signing-certificate, and signature-timestamp extraction for `XadesXmlParser`.
extension XadesXmlParser {
  /// Validates and appends one `ds:Reference` inside `ds:SignedInfo`.
  internal static func appendReference(
    _ reference: XmlElement,
    into parsed: inout AsicVerification.ParsedSignature
  ) {
    let dsig = XadesSignature.namespaceDsig
    if !Self.hasValidReferenceChildren(reference) {
      parsed.hasStructuralError = true
    }
    let transformsContainer = reference.child(dsig, Element.transforms)
    let transformElements: [XmlElement]
    if let transformsContainer {
      let children = transformsContainer.children
      if children.isEmpty || !children.allSatisfy({ $0.matches(dsig, Element.transform) }) {
        parsed.hasStructuralError = true
      }
      transformElements = children.filter { $0.matches(dsig, Element.transform) }
    } else {
      transformElements = []
    }

    let digestMethodElement = reference.child(dsig, Element.digestMethod)
    let digestValueElement = reference.child(dsig, Element.digestValue)
    guard
      let uri = reference.attribute(Attribute.uri),
      let methodUri = digestMethodElement?.attribute(Attribute.algorithm),
      let digestValueElement,
      digestValueElement.children.isEmpty,
      let digestValue = Self.base64(digestValueElement.text)
    else {
      parsed.references.markIncomplete()
      return
    }
    guard let digestMethod = AsicVerification.XmlDigestMethod(uri: methodUri) else {
      parsed.references.markUnsupported()
      return
    }
    guard digestValue.count == digestMethod.byteCount else {
      parsed.references.markIncomplete()
      return
    }
    let transforms = transformElements.map { $0.attribute(Attribute.algorithm) ?? "" }
    parsed.references.append(
      AsicVerification.ParsedReference(
        identifier: reference.attribute(Attribute.identifier),
        uri: uri,
        type: reference.attribute(Attribute.type),
        transforms: transforms,
        transformElements: transformElements,
        digestMethod: digestMethod,
        digestValue: digestValue
      ))
  }

  /// Checks `(Transforms?, DigestMethod, DigestValue)` sequence on `ds:Reference`.
  private static func hasValidReferenceChildren(_ reference: XmlElement) -> Bool {
    let dsig = XadesSignature.namespaceDsig
    var iterator = reference.children.makeIterator()
    var current = iterator.next()
    if let candidate = current, candidate.matches(dsig, Element.transforms) {
      current = iterator.next()
    }
    guard
      let digestMethod = current,
      digestMethod.matches(dsig, Element.digestMethod),
      digestMethod.children.isEmpty,
      let digestValue = iterator.next(),
      digestValue.matches(dsig, Element.digestValue),
      iterator.next() == nil
    else {
      return false
    }
    return true
  }

  /// Reads all `xades:Cert` entries of a `SigningCertificate` or `SigningCertificateV2` element.
  internal static func appendCertReferences(
    in container: XmlElement,
    property: AsicVerification.SigningCertificateProperty,
    into parsed: inout AsicVerification.ParsedSignature
  ) {
    let xades = XadesSignature.namespaceXades
    let certs = container.children(xades, Element.cert)
    if certs.isEmpty || certs.count != container.children.count {
      parsed.hasStructuralError = true
    }
    for cert in certs {
      Self.appendOneCertReference(cert, property: property, into: &parsed)
    }
  }

  /// Reads one `xades:Cert` element into `parsed.signingCertificates`.
  private static func appendOneCertReference(
    _ cert: XmlElement,
    property: AsicVerification.SigningCertificateProperty,
    into parsed: inout AsicVerification.ParsedSignature
  ) {
    let xades = XadesSignature.namespaceXades
    let digests = cert.children(xades, Element.certDigest)
    guard digests.count == 1, let certDigest = digests.first else {
      parsed.signingCertificates.markIncomplete()
      return
    }
    let issuerSerialResult = Self.readIssuerSerial(from: cert)
    let expectedChildren = digests.count + (issuerSerialResult.value == nil ? 0 : 1)
    guard issuerSerialResult.isValid, cert.children.count == expectedChildren else {
      parsed.signingCertificates.markIncomplete()
      return
    }
    guard let parsedDigest = Self.readCertDigest(certDigest) else {
      parsed.signingCertificates.markIncomplete()
      return
    }
    guard let method = AsicVerification.XmlDigestMethod(uri: parsedDigest.methodUri) else {
      parsed.signingCertificates.markUnsupported()
      return
    }
    guard parsedDigest.value.count == method.byteCount else {
      parsed.signingCertificates.markIncomplete()
      return
    }
    parsed.signingCertificates.append(
      AsicVerification.SigningCertificateReference(
        property: property,
        method: method,
        value: parsedDigest.value,
        issuerSerial: issuerSerialResult.value
      ))
  }

  /// Validates `(DigestMethod, DigestValue)` on `xades:CertDigest` and returns algorithm URI and bytes.
  private static func readCertDigest(
    _ certDigest: XmlElement
  ) -> (methodUri: String, value: Data)? {
    let dsig = XadesSignature.namespaceDsig
    var iterator = certDigest.children.makeIterator()
    guard
      let methodElement = iterator.next(),
      methodElement.matches(dsig, Element.digestMethod),
      methodElement.children.isEmpty,
      let methodUri = methodElement.attribute(Attribute.algorithm),
      let valueElement = iterator.next(),
      valueElement.matches(dsig, Element.digestValue),
      valueElement.children.isEmpty,
      iterator.next() == nil,
      let value = Self.base64(valueElement.text)
    else {
      return nil
    }
    return (methodUri, value)
  }

  /// Parses optional `IssuerSerialV2` or `IssuerSerial` from `cert`.
  private static func readIssuerSerial(
    from cert: XmlElement
  ) -> (isValid: Bool, value: AsicVerification.StatedIssuerSerial?) {
    let xades = XadesSignature.namespaceXades
    let dsig = XadesSignature.namespaceDsig
    let v2List = cert.children(xades, Element.issuerSerialV2)
    let v1List = cert.children(xades, Element.issuerSerial)
    if v2List.count > 1 || v1List.count > 1 || (!v2List.isEmpty && !v1List.isEmpty) {
      return (false, nil)
    }
    if let versionTwo = v2List.first {
      guard versionTwo.children.isEmpty, let der = Self.base64(versionTwo.text) else {
        return (false, nil)
      }
      return (true, .der(der))
    }
    if let versionOne = v1List.first {
      let names = versionOne.children(dsig, Element.x509IssuerName)
      let serials = versionOne.children(dsig, Element.x509SerialNumber)
      guard
        names.count == 1,
        serials.count == 1,
        versionOne.children.count == names.count + serials.count,
        let name = names.first,
        let serial = serials.first,
        name.children.isEmpty,
        serial.children.isEmpty
      else {
        return (false, nil)
      }
      let issuerText = Self.trimmed(name.text)
      let serialText = Self.trimmed(serial.text)
      guard !issuerText.isEmpty, !serialText.isEmpty else {
        return (false, nil)
      }
      return (true, .text(issuerName: issuerText, serialNumber: serialText))
    }
    return (true, nil)
  }

  /// Decodes `EncapsulatedTimeStamp` tokens in `stamp` paired with canonical `ds:SignatureValue`.
  internal static func appendSignatureTimestamps(
    from stamp: XmlElement,
    into parsed: inout AsicVerification.ParsedSignature
  ) {
    let dsig = XadesSignature.namespaceDsig
    let xades = XadesSignature.namespaceXades
    let c14nElements = stamp.children(dsig, Element.canonicalizationMethod)
    let tokenElements = stamp.children(xades, Element.encapsulatedTimeStamp)
    if tokenElements.isEmpty || stamp.children.count != c14nElements.count + tokenElements.count {
      parsed.hasStructuralError = true
    }
    let c14n: XmlCanonicalization?
    if c14nElements.isEmpty {
      c14n = .inclusive
    } else if c14nElements.count == 1 {
      c14n = XmlCanonicalization(method: c14nElements[0])
    } else {
      parsed.hasStructuralError = true
      c14n = nil
    }
    let imprintInput = c14n.flatMap { method in
      parsed.signatureValueElement.flatMap { sigVal in
        XmlCanonicalizer.canonicalize(sigVal, method: method, omitting: nil)
      }
    }
    for tokenElement in tokenElements {
      guard tokenElement.children.isEmpty, let token = Self.base64(tokenElement.text) else {
        parsed.hasStructuralError = true
        continue
      }
      parsed.signatureTimestamps.append(
        AsicVerification.ParsedSignatureTimestamp(token: token, imprintInput: imprintInput))
    }
  }
}
