// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// A `ds:DigestValue` under a known `ds:DigestMethod`, its length the
/// method's (W3C XML Signature 1.1 section 4.4.3.4).
internal struct XmlDigestValue: Equatable {
  /// The method.
  internal let method: AsicVerification.XmlDigestMethod

  /// The value.
  internal let value: Data

  /// Reads the `ds:DigestMethod` and `ds:DigestValue` children of
  /// `parent`.
  ///
  /// Throws `TrustedListError.malformed(what)` when a child is absent
  /// or the value is not base64 of the method's length, and
  /// `.unverifiable(what)` when the method is one the verifier does
  /// not compute.
  internal init(parent: XmlElement, what: String) throws {
    guard
      let valueElement = parent.child(
        XadesSignature.namespaceDsig, XadesXmlParser.Element.digestValue),
      let decoded = XadesXmlParser.base64(valueElement.text)
    else {
      throw TrustedListError.malformed(what)
    }
    guard
      let uri = parent.child(XadesSignature.namespaceDsig, XadesXmlParser.Element.digestMethod)?
        .attribute(XadesXmlParser.Attribute.algorithm),
      let named = AsicVerification.XmlDigestMethod(uri: uri)
    else {
      throw TrustedListError.unverifiable(what)
    }
    guard decoded.count == named.hash(Data()).count else {
      throw TrustedListError.malformed(what)
    }
    method = named
    value = decoded
  }

  /// Whether `input` digests to this value.
  internal func matches(_ input: Data) -> Bool {
    method.hash(input) == value
  }
}
