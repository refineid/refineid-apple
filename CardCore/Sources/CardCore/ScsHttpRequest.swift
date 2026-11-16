// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// One parsed SCS request head.
///
/// The SCS serves exactly one request per connection and closes it, so
/// the head plus a `Content-Length` body is the whole exchange. Every
/// parsed wire request validates its `Host` header against the loopback
/// allowlist (`127.0.0.1` or `localhost`, optional `:53952`) and
/// rejects duplicate framing or routing headers.
public struct ScsHttpRequest: Equatable, Sendable {
  private struct ParsedHeaders {
    var host: String?
    var origin: String?
    var contentType: String?
    var length: Int?
  }

  private static let requestLineMinimumParts = 2

  /// The request method, verbatim.
  public let method: String

  /// The request path with any query string removed.
  public let path: String

  /// The Origin header, when the browser sent one.
  public let origin: String?

  /// The Content-Type header, when present.
  public let contentType: String?

  /// The Content-Length header, parsed; zero when absent.
  public let bodyLength: Int

  /// Lowercase media-type essence before any `;` parameter.
  public var contentTypeEssence: String? {
    guard let contentType else { return nil }
    let essence =
      contentType
      .split(separator: ";", maxSplits: 1, omittingEmptySubsequences: false)
      .first?
      .trimmingCharacters(in: .whitespaces)
      .lowercased()
    guard let essence, !essence.isEmpty else { return nil }
    return essence
  }

  /// Whether the request can be answered immediately without entering
  /// the serial card-signing queue.
  public var isStatelessFastPath: Bool {
    if let origin, ScsOriginPolicy.refusal(forPresentOrigin: origin) != nil {
      return true
    }
    guard method == "POST", path == "/sign" else {
      return true
    }
    guard let essence = contentTypeEssence else {
      return true
    }
    return essence != "application/json" && essence != "application/jwt"
  }

  /// Builds a request head for tests and local callers.
  public init(
    method: String,
    path: String,
    origin: String?,
    contentType: String?,
    bodyLength: Int
  ) {
    self.method = method
    self.path = path
    self.origin = origin
    self.contentType = contentType
    self.bodyLength = bodyLength
  }

  /// Parses one head block (the bytes before the blank line).
  ///
  /// Returns nil when the block is not UTF-8, lacks a valid request
  /// line, omits or duplicates `Host`, names a non-loopback `Host`, or
  /// carries duplicate framing headers.
  public static func parse(head: Data) -> Self? {
    guard let text = String(data: head, encoding: .utf8) else { return nil }
    var lines = text.components(separatedBy: "\r\n")
    guard !lines.isEmpty else { return nil }
    let requestLine = lines.removeFirst()
    let requestParts = requestLine.split(separator: " ")
    guard requestParts.count >= Self.requestLineMinimumParts else { return nil }
    let parsedMethod = String(requestParts[0])
    let requestTarget = String(requestParts[1])
    let parsedPath =
      requestTarget.split(separator: "?").first.map(String.init) ?? requestTarget
    guard let headers = parseHeaders(lines) else { return nil }
    return Self(
      method: parsedMethod,
      path: parsedPath,
      origin: headers.origin,
      contentType: headers.contentType,
      bodyLength: headers.length ?? 0
    )
  }

  private static func parseHeaders(_ lines: [String]) -> ParsedHeaders? {
    var headers = ParsedHeaders()
    for line in lines where !line.isEmpty {
      guard let separator = line.firstIndex(of: ":") else { return nil }
      let name = line[line.startIndex..<separator].trimmingCharacters(in: .whitespaces)
      let value = line[line.index(after: separator)...].trimmingCharacters(in: .whitespaces)
      guard applyHeader(name: name, value: value, into: &headers) else {
        return nil
      }
    }
    guard headers.host != nil else { return nil }
    return headers
  }

  private static func applyHeader(
    name: String,
    value: String,
    into headers: inout ParsedHeaders
  ) -> Bool {
    switch name.lowercased() {
    case "host":
      guard headers.host == nil, ScsOriginPolicy.isAllowedHostHeader(value) else { return false }
      headers.host = value
      return true

    case "origin":
      guard headers.origin == nil else { return false }
      headers.origin = value
      return true

    case "content-type":
      guard headers.contentType == nil else { return false }
      headers.contentType = value
      return true

    case "content-length":
      guard headers.length == nil, let declared = Int(value), declared >= 0 else { return false }
      headers.length = declared
      return true

    case "transfer-encoding":
      return false

    default:
      return true
    }
  }
}
