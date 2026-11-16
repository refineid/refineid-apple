// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

extension TimestampCmsVerifier {
  /// Matches either CMS SignerIdentifier form to an embedded certificate.
  internal static func identifier(
    _ identifier: DerReader.Element,
    in token: Data,
    matches certificate: Data
  ) -> Bool {
    guard let facts = CertificateFacts(der: certificate) else { return false }
    if identifier.tag == DerValues.tagSequence {
      var reader = DerReader(token, within: identifier)
      guard
        let issuer = reader.next(),
        let serial = reader.next(), serial.tag == DerValues.tagInteger,
        reader.isAtEnd
      else { return false }
      return reader.data(of: issuer) == facts.issuerName
        && reader.contentData(of: serial) == facts.serialNumber
    }
    if identifier.tag == DerValues.tagContext0Primitive {
      return facts.subjectKeyIdentifier
        == DerReader(token).contentData(of: identifier)
    }
    return false
  }
}
