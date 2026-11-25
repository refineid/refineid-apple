// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// Validated HTTPS relying-party origin (`https://<host>[:<port>]`).
///
/// Rejects non-HTTPS schemes, embedded credentials, paths, query strings,
/// fragments, and trailing slashes so the exact origin string hashed into
/// Web eID authentication tokens matches the browser's `URL.origin`.
public struct WebEidOrigin: Codable, Equatable, Hashable, Sendable {
  /// Exact serialized HTTPS origin (`https://example.ee` or `https://example.ee:8443`).
  public let value: String

  /// Host component for concise user-facing display.
  public let host: String

  /// Validates and wraps a raw origin string.
  public init?(_ raw: String) {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard
      trimmed == raw,
      !trimmed.isEmpty,
      !trimmed.hasSuffix("/"),
      let components = URLComponents(string: trimmed),
      components.scheme?.lowercased() == WebEidValues.requiredOriginScheme,
      let parsedHost = components.host,
      !parsedHost.isEmpty,
      components.user == nil,
      components.password == nil,
      components.path.isEmpty,
      components.query == nil,
      components.fragment == nil
    else {
      return nil
    }
    value = trimmed
    host = parsedHost
  }

  /// Decodes and validates an HTTPS origin string.
  public init(from decoder: any Decoder) throws {
    let container = try decoder.singleValueContainer()
    let raw = try container.decode(String.self)
    guard let validated = Self(raw) else {
      throw DecodingError.dataCorruptedError(
        in: container,
        debugDescription: "Invalid HTTPS Web eID origin"
      )
    }
    self = validated
  }

  /// Encodes the validated origin string.
  public func encode(to encoder: any Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(value)
  }
}
