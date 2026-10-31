// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// The values the parser collects for the innermost open signature.
extension XadesXmlParser {
  /// Handles the end of a signing-certificate Cert, one of its fields,
  /// or a validation value.
  internal func handleOtherEnd(path: [String], text: String) {
    if Path.signingCertificates.contains(path) {
      appendCurrentCertificate(property: path.dropLast().last)
      updateOpen { open in open.certificate = PendingCertificate() }
    } else if let field = CertificateField(path: path) {
      handleCertificateField(field, text: text)
    } else {
      handleValidationValue(path: path, text: text)
    }
  }

  /// Starts a signing-certificate Cert, or reads its digest method.
  internal func handleCertificateStart(path: [String], attributeDict: [String: String]) {
    if Path.signingCertificates.contains(path) {
      updateOpen { open in open.certificate = PendingCertificate() }
    } else if CertificateField(path: path) == .digestMethod {
      updateOpen { open in
        open.certificate.digestMethod = attributeDict[Attribute.algorithm]
      }
    }
  }

  /// Records one text field of the signing-certificate Cert in progress.
  internal func handleCertificateField(_ field: CertificateField, text: String) {
    updateOpen { open in
      switch field {
      case .digestMethod:
        break

      case .digestValue:
        open.certificate.digestValue = Self.base64(text)
        if open.certificate.digestValue == nil { open.certificate.unreadable = true }

      case .issuerSerialV2:
        open.certificate.issuerSerialV2 = Self.base64(text)
        if open.certificate.issuerSerialV2 == nil { open.certificate.unreadable = true }

      case .issuerName:
        open.certificate.issuerName = Self.trimmed(text)

      case .serialNumber:
        open.certificate.serialNumber = Self.trimmed(text)
      }
    }
  }

  /// Adds the signing-certificate Cert just closed, or marks the
  /// property as carrying one that cannot be checked.
  internal func appendCurrentCertificate(property element: String?) {
    guard let pending = innermost?.certificate else { return }
    let property: AsicVerification.SigningCertificateProperty =
      element == Element.signingCertificate ? .versionOne : .versionTwo
    let issuerSerial: AsicVerification.StatedIssuerSerial?
    switch (pending.issuerSerialV2, pending.issuerName, pending.serialNumber) {
    case (let der?, nil, nil):
      issuerSerial = .der(der)

    case (nil, let name?, let serial?):
      issuerSerial = .text(issuerName: name, serialNumber: serial)

    case (nil, nil, nil):
      issuerSerial = nil

    default:
      update { signature in signature.signingCertificates.markIncomplete() }
      return
    }
    guard
      !pending.unreadable,
      let methodUri = pending.digestMethod,
      let value = pending.digestValue
    else {
      update { signature in signature.signingCertificates.markIncomplete() }
      return
    }
    guard let method = AsicVerification.XmlDigestMethod(uri: methodUri) else {
      update { signature in signature.signingCertificates.markUnsupported() }
      return
    }
    let reference = AsicVerification.SigningCertificateReference(
      property: property, method: method, value: value, issuerSerial: issuerSerial)
    update { signature in signature.signingCertificates.append(reference) }
  }

  /// Collects one certificate, CRL or OCSP value from a validation-data
  /// container (EN 319 132-1 clauses 5.4.1 and 5.4.2).
  internal func handleValidationValue(path: [String], text: String) {
    guard
      let container = Path.validationContainers.first(where: { prefix in
        path.count > prefix.count && Array(path.prefix(prefix.count)) == prefix
      }),
      let value = Self.base64(text)
    else {
      return
    }
    switch Array(path.dropFirst(container.count)) {
    case Path.certificateValue:
      update { signature in signature.certificateValues.append(value) }

    case Path.crlValue:
      update { signature in signature.crlValues.append(value) }

    case Path.ocspValue:
      update { signature in signature.ocspValues.append(value) }

    default:
      break
    }
  }

  /// Adds the reference just closed, or marks the signature as
  /// carrying one that cannot be checked.
  internal func appendCurrentReference() {
    guard
      let pending = innermost?.reference,
      let uri = pending.uri,
      let methodUri = pending.digestMethod,
      let digestValue = pending.digestValue
    else {
      update { signature in signature.references.markIncomplete() }
      return
    }
    guard let digestMethod = AsicVerification.XmlDigestMethod(uri: methodUri) else {
      update { signature in signature.references.markUnsupported() }
      return
    }
    let reference = AsicVerification.ParsedReference(
      identifier: pending.identifier,
      uri: uri,
      type: pending.type,
      transforms: pending.transforms,
      digestMethod: digestMethod,
      digestValue: digestValue
    )
    update { signature in signature.references.append(reference) }
  }
}
