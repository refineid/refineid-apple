// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// SubjectKeyIdentifier parsing used by `CertificateFacts` (RFC 5280 section 4.2.1.2).
extension CertificateFacts {
  /// The SubjectKeyIdentifier status collected across certificate extensions.
  internal enum SubjectKeyIdentifier: Equatable {
    /// No SubjectKeyIdentifier extension has been seen yet.
    case absent

    /// A SubjectKeyIdentifier or enclosing extension structure is malformed,
    /// marked critical, or duplicated.
    case invalid

    /// One valid non-critical SubjectKeyIdentifier was found.
    case value(Data)

    /// The key-identifier octets when valid, or nil when absent or invalid.
    internal var octets: Data? {
      guard case .value(let octets) = self else { return nil }
      return octets
    }
  }

  /// Records one extension entry's SubjectKeyIdentifier verdict, failing closed
  /// on duplicates or malformed extension structures.
  internal static func addSubjectKeyIdentifier(
    from entry: DerReader.Element,
    der: Data,
    to facts: inout ExtensionFacts
  ) {
    guard let parsed = Self.subjectKeyIdentifier(of: entry, in: der) else {
      return
    }
    if facts.subjectKeyIdentifier == .absent {
      facts.subjectKeyIdentifier = parsed
    } else {
      facts.subjectKeyIdentifier = .invalid
    }
  }

  /// Parses `id-ce-subjectKeyIdentifier` (`2.5.29.14`) as a non-critical
  /// OCTET STRING inside `extnValue`, returning nil for valid other extensions.
  private static func subjectKeyIdentifier(
    of entry: DerReader.Element,
    in der: Data
  ) -> SubjectKeyIdentifier? {
    guard entry.tag == DerValues.tagSequence else { return .invalid }
    var reader = DerReader(der, within: entry)
    guard
      let oid = reader.next(),
      oid.tag == DerValues.tagObjectIdentifier
    else {
      return .invalid
    }
    guard
      reader.data(of: oid)
        == DerEncoder.objectIdentifier(SignOids.subjectKeyIdentifier)
    else {
      var value = reader.next()
      if value?.tag == DerValues.tagBoolean {
        value = reader.next()
      }
      guard
        let value,
        value.tag == DerValues.tagOctetString,
        reader.isAtEnd
      else {
        return .invalid
      }
      return nil
    }
    guard
      let value = reader.next(),
      value.tag == DerValues.tagOctetString,
      reader.isAtEnd
    else {
      return .invalid
    }
    let encoded = reader.contentData(of: value)
    var inner = DerReader(encoded)
    guard
      let identifier = inner.next(),
      identifier.tag == DerValues.tagOctetString,
      inner.isAtEnd
    else {
      return .invalid
    }
    return .value(inner.contentData(of: identifier))
  }
}
