// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// Validation and display sanitization for SCS `Origin` and `Host`
/// headers (DVV SCS specification v1.3 §2.1; RFC 6454).
public enum ScsOriginPolicy {
  private static let httpsPrefix = "https://"
  private static let httpPrefix = "http://"
  private static let maximumPort = 65_535

  /// Why a present `Origin` header is refused before route or card
  /// handling, or nil when it is a well-formed `https://` web origin.
  public static func refusal(forPresentOrigin origin: String) -> String? {
    if origin.unicodeScalars.contains(where: { scalar in
      ScsValues.isForbiddenOriginScalar(scalar.value) || !scalar.isASCII
    }) {
      return "Origin contains disallowed characters"
    }
    if origin.lowercased().hasPrefix(Self.httpPrefix) {
      return
        "Origin uses http instead of https; insecure web pages cannot use the signing service"
    }
    guard origin.hasPrefix(Self.httpsPrefix) else {
      return "Origin must use the https:// scheme"
    }
    let authority = String(origin.dropFirst(Self.httpsPrefix.count))
    guard isValidAuthority(authority) else {
      return "Origin must be a valid https:// web origin"
    }
    return nil
  }

  /// Formats an `Origin` header for holder-facing display: control,
  /// line-break, and bidirectional-override scalars stripped, bounded
  /// to a single readable line.
  public static func sanitizedForDisplay(_ origin: String?) -> String? {
    guard let origin else { return nil }
    let filtered = origin.unicodeScalars.filter { scalar in
      !ScsValues.isForbiddenOriginScalar(scalar.value)
    }
    let cleaned = String(String.UnicodeScalarView(filtered))
      .trimmingCharacters(in: .whitespacesAndNewlines)
    guard !cleaned.isEmpty else {
      return "(invalid Origin)"
    }
    if cleaned.count > ScsValues.originDisplayMaximumCharacters {
      let prefixCount = 48
      let suffixCount = ScsValues.originDisplayMaximumCharacters - prefixCount - 1
      return String(cleaned.prefix(prefixCount)) + "…" + String(cleaned.suffix(suffixCount))
    }
    return cleaned
  }

  /// Strips control and bidirectional scalars from a cardholder subject
  /// summary so card data cannot inject prompt lines or reorder text.
  public static func sanitizedSignerName(_ summary: String?) -> String? {
    guard let summary else { return nil }
    let filtered = summary.unicodeScalars.filter { scalar in
      !ScsValues.isForbiddenOriginScalar(scalar.value)
    }
    let cleaned = String(String.UnicodeScalarView(filtered))
      .trimmingCharacters(in: .whitespacesAndNewlines)
    return cleaned.isEmpty ? nil : cleaned
  }

  /// Safe `Access-Control-Allow-Origin` header value: echoes a valid
  /// `https://` origin, `"*"` when no origin was sent, or `"null"` when
  /// the caller sent an invalid or control-carrying origin.
  public static func reflectedCorsOrigin(_ origin: String?) -> String {
    guard let origin else { return "*" }
    guard refusal(forPresentOrigin: origin) == nil else { return "null" }
    return origin
  }

  /// Whether `host` names the loopback SCS endpoint (`127.0.0.1` or
  /// `localhost`, with or without `:53952`).
  public static func isAllowedHostHeader(_ host: String) -> Bool {
    if host.unicodeScalars.contains(where: { scalar in
      ScsValues.isForbiddenOriginScalar(scalar.value) || !scalar.isASCII
    }) {
      return false
    }
    let normalized = host.lowercased()
    let portSuffix = ":\(ScsValues.port)"
    return normalized == "127.0.0.1"
      || normalized == "127.0.0.1" + portSuffix
      || normalized == "localhost"
      || normalized == "localhost" + portSuffix
  }

  private static func isValidAuthority(_ authority: String) -> Bool {
    guard
      !authority.isEmpty,
      !authority.contains("/"),
      !authority.contains("?"),
      !authority.contains("#"),
      !authority.contains("@"),
      !authority.contains(";"),
      !authority.contains(where: \.isWhitespace)
    else {
      return false
    }
    let host: Substring
    let portText: Substring?
    if authority.hasPrefix("[") {
      guard let closing = authority.firstIndex(of: "]") else { return false }
      let afterClosing = authority.index(after: closing)
      host = authority[authority.startIndex..<afterClosing]
      if afterClosing == authority.endIndex {
        portText = nil
      } else {
        guard authority[afterClosing] == ":" else { return false }
        portText = authority[authority.index(after: afterClosing)...]
      }
    } else if let colon = authority.firstIndex(of: ":") {
      host = authority[authority.startIndex..<colon]
      portText = authority[authority.index(after: colon)...]
    } else {
      host = authority[...]
      portText = nil
    }
    if let portText, !isValidPort(portText) {
      return false
    }
    return isValidHost(host)
  }

  private static func isValidPort(_ portText: Substring) -> Bool {
    guard
      !portText.isEmpty,
      !portText.hasPrefix("0"),
      portText.allSatisfy(\.isWholeNumber),
      let port = Int(portText),
      (1...Self.maximumPort).contains(port)
    else {
      return false
    }
    return true
  }

  private static func isValidHost(_ host: Substring) -> Bool {
    if host.hasPrefix("["), host.hasSuffix("]") {
      let inner = host.dropFirst().dropLast()
      return !inner.isEmpty
        && inner.allSatisfy { char in char.isHexDigit || char == ":" }
    }
    guard
      !host.isEmpty,
      !host.hasPrefix("."),
      !host.hasSuffix("."),
      !host.contains("..")
    else {
      return false
    }
    return host.allSatisfy { char in
      char.isASCII && (char.isLetter || char.isNumber || char == "-" || char == ".")
    }
  }
}
