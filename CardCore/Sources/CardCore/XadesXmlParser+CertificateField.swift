// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// The parts of a signing-certificate `xades:Cert` the parser reads.
extension XadesXmlParser {
  /// The parts of one `xades:Cert` the parser reads.
  internal enum CertificateField {
    case digestMethod
    case digestValue
    case issuerSerialV2
    case issuerName
    case serialNumber

    /// The field's path below `xades:Cert`.
    private var below: [String] {
      switch self {
      case .digestMethod:
        [Element.certDigest, Element.digestMethod]

      case .digestValue:
        [Element.certDigest, Element.digestValue]

      case .issuerSerialV2:
        [Element.issuerSerialV2]

      case .issuerName:
        [Element.issuerSerial, Element.x509IssuerName]

      case .serialNumber:
        [Element.issuerSerial, Element.x509SerialNumber]
      }
    }

    /// The field `path` names inside a signing-certificate Cert.
    internal init?(path: [String]) {
      let fields: [Self] = [
        .digestMethod, .digestValue, .issuerSerialV2, .issuerName, .serialNumber,
      ]
      guard
        let found = fields.first(where: { field in
          path.count > field.below.count
            && Array(path.suffix(field.below.count)) == field.below
            && Path.signingCertificates.contains(Array(path.dropLast(field.below.count)))
        })
      else {
        return nil
      }
      self = found
    }
  }
}
