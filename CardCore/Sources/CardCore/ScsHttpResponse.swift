// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// Builders for the SCS's HTTP responses.
///
/// Every response carries sanitized CORS headers and closes its
/// single-use connection. Reflected `Origin` values pass through
/// `ScsOriginPolicy.reflectedCorsOrigin`, and every header value strips
/// control characters before serialization.
public enum ScsHttpResponse {
  /// A JSON response with CORS headers.
  public static func json(status: Int, body: Data, origin: String?) -> Data {
    build(
      status: status,
      headers: corsHeaders(origin: origin) + [("Content-Type", "application/json")],
      body: body
    )
  }

  /// A compact JWT/JWE response with CORS headers.
  public static func jwt(_ compact: String, origin: String?) -> Data {
    build(
      status: ScsValues.httpOk,
      headers: corsHeaders(origin: origin) + [("Content-Type", "application/jwt")],
      body: Data(compact.utf8)
    )
  }

  /// A plain-text response with CORS headers.
  public static func text(status: Int, body: String, origin: String?) -> Data {
    build(
      status: status,
      headers: corsHeaders(origin: origin) + [("Content-Type", "text/plain; charset=utf-8")],
      body: Data(body.utf8)
    )
  }

  /// The CORS preflight acknowledgement for served routes.
  public static func preflight(origin: String?) -> Data {
    build(status: ScsValues.httpOk, headers: corsHeaders(origin: origin), body: Data())
  }

  private static func corsHeaders(origin: String?) -> [(String, String)] {
    [
      ("Access-Control-Allow-Origin", ScsOriginPolicy.reflectedCorsOrigin(origin)),
      ("Access-Control-Allow-Methods", "GET, POST"),
      ("Access-Control-Allow-Headers", "Accept, Content-Type"),
      ("Access-Control-Max-Age", String(ScsValues.preflightMaxAgeSeconds)),
      ("Vary", "Origin"),
    ]
  }

  private static func sanitizeHeaderField(_ value: String) -> String {
    let filtered = value.unicodeScalars.filter { scalar in
      !CharacterSet.controlCharacters.contains(scalar)
    }
    return String(String.UnicodeScalarView(filtered))
  }

  private static func build(
    status: Int,
    headers: [(String, String)],
    body: Data
  ) -> Data {
    var head = "HTTP/1.1 \(status) \(reason(for: status))\r\n"
    head += "Content-Length: \(body.count)\r\n"
    head += "Connection: close\r\n"
    for (name, value) in headers {
      head += "\(sanitizeHeaderField(name)): \(sanitizeHeaderField(value))\r\n"
    }
    head += "\r\n"
    var out = Data(head.utf8)
    out.append(body)
    return out
  }

  private static func reason(for status: Int) -> String {
    switch status {
    case ScsValues.httpOk:
      "OK"

    case ScsValues.httpForbidden:
      "Forbidden"

    case ScsValues.httpNotFound:
      "Not Found"

    default:
      "Status"
    }
  }
}
