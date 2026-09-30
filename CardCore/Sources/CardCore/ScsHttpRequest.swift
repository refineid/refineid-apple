// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// One parsed SCS request head.
///
/// The SCS serves exactly one request per connection and closes it, so
/// the head plus a `Content-Length` body is the whole exchange. That
/// is a local framing choice rather than a specified one: the
/// specification's own examples use `Connection: keep-alive` (v1.3
/// §2.4), and single-use connections remove any question of one
/// request's bytes being read as another's. Only the fields the
/// protocol acts on are kept: the method and path route, the Origin
/// binds challenges and CORS answers, the content type selects the
/// JSON or JWT branch.
public struct ScsHttpRequest: Equatable, Sendable {
  /// A request line names at least a method and a target.
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
  /// Returns nil when the block is not ASCII/UTF-8 or has no request
  /// line; unknown headers are ignored.
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

    var parsedOrigin: String?
    var parsedContentType: String?
    var parsedLength = 0
    for line in lines {
      guard let separator = line.firstIndex(of: ":") else { continue }
      let name = line[line.startIndex..<separator].trimmingCharacters(in: .whitespaces)
      let value = line[line.index(after: separator)...].trimmingCharacters(in: .whitespaces)
      if name.caseInsensitiveCompare("Origin") == .orderedSame {
        parsedOrigin = value
      } else if name.caseInsensitiveCompare("Content-Type") == .orderedSame {
        parsedContentType = value
      } else if name.caseInsensitiveCompare("Content-Length") == .orderedSame {
        // A declared length that is not a non-negative integer is a
        // malformed head: falling back to zero would accept garbage or an
        // overflowing number as a valid empty body, and a negative count
        // would reach the body assembly.
        guard let declared = Int(value), declared >= 0 else { return nil }
        parsedLength = declared
      }
    }
    return Self(
      method: parsedMethod,
      path: parsedPath,
      origin: parsedOrigin,
      contentType: parsedContentType,
      bodyLength: parsedLength
    )
  }
}
