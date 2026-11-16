// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation
import Security

/// The validity window an X.509 certificate carries.
///
/// The window is read from the certificate's own DER rather than through
/// `SecCertificateCopyNotValidBeforeDate`, which Security introduced in a
/// release later than the oldest system this module supports. Both read the
/// same RFC 5280 field, and the time forms are parsed through `DerTime`.
internal enum CertificateValidity {
  /// The window of a certificate Security has already accepted.
  internal static func window(
    of certificate: SecCertificate
  ) -> (notBefore: Date, notAfter: Date)? {
    Self.window(inDer: SecCertificateCopyData(certificate) as Data)
  }

  /// The window of an encoded certificate, or nil when it carries no
  /// well-formed validity sequence.
  internal static func window(
    inDer der: Data
  ) -> (notBefore: Date, notAfter: Date)? {
    guard let validity = Self.validityElement(in: der) else { return nil }
    var reader = DerReader(der, within: validity)
    guard
      let notBefore = reader.next(),
      let notAfter = reader.next(),
      let start = DerTime.rfc5280Time(in: reader, element: notBefore),
      let end = DerTime.rfc5280Time(in: reader, element: notAfter)
    else {
      return nil
    }
    return (start, end)
  }

  /// The `validity` SEQUENCE inside the certificate's TBSCertificate.
  ///
  /// RFC 5280 orders the fields version, serialNumber, signature, issuer,
  /// validity, so the walk skips the optional version and then counts three
  /// elements on.
  private static func validityElement(in der: Data) -> DerReader.Element? {
    var outer = DerReader(der)
    guard
      let certificate = outer.next(),
      certificate.tag == DerValues.tagSequence
    else {
      return nil
    }
    var certificateReader = DerReader(der, within: certificate)
    guard let tbs = certificateReader.next() else { return nil }
    var reader = DerReader(der, within: tbs)
    guard var element = reader.next() else { return nil }
    if element.tag == DerValues.tagContext0Constructed {
      guard let following = reader.next() else { return nil }
      element = following
    }
    guard
      element.tag == DerValues.tagInteger,
      reader.next() != nil,
      reader.next() != nil,
      let validity = reader.next(),
      validity.tag == DerValues.tagSequence
    else {
      return nil
    }
    return validity
  }
}
