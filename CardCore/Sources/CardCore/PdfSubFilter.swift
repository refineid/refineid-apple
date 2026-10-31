// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

/// The /SubFilter a PDF signature dictionary declares (ISO 32000-1
/// clause 12.8.3; EN 319 142-1 clause 5.3).
public enum PdfSubFilter: Sendable, Equatable {
  /// `ETSI.CAdES.detached`, a PAdES baseline signature.
  case cades

  /// Any other name, or none.
  case other

  /// `adbe.pkcs7.detached`, which EN 319 142-2 clause 4.2.3 admits.
  case pkcs7

  /// `ETSI.RFC3161`, a document timestamp.
  case rfc3161

  /// The name of a PAdES baseline signature.
  private static let cadesName = "ETSI.CAdES.detached"

  /// The name of a PKCS #7 detached signature.
  private static let pkcs7Name = "adbe.pkcs7.detached"

  /// The name of a document timestamp.
  private static let rfc3161Name = "ETSI.RFC3161"

  /// The subfilter a name without its solidus names.
  internal init(name: String) {
    switch name {
    case Self.cadesName:
      self = .cades

    case Self.pkcs7Name:
      self = .pkcs7

    case Self.rfc3161Name:
      self = .rfc3161

    default:
      self = .other
    }
  }
}
