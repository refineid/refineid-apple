// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// Incremental assembly of one SCS HTTP exchange from transport bytes.
///
/// The transport hands over whatever it has read so far; assembly
/// answers whether the buffer already holds the complete request. The
/// caller keeps accumulating until `complete` or `invalid` - one
/// request per connection, which this implementation chooses so a
/// connection's bytes can only ever form one request.
public enum ScsHttpAssembly: Equatable, Sendable {
  /// The buffer holds a complete request head and body.
  case complete(ScsHttpExchange)

  /// The buffer can never become a valid request; close the
  /// connection.
  case invalid

  /// The buffer is a valid prefix; read more bytes.
  case needMoreData

  /// Classifies the buffer as read so far.
  public static func assemble(buffer: Data) -> Self {
    let headEnd = Data("\r\n\r\n".utf8)
    guard let boundary = buffer.range(of: headEnd) else {
      guard buffer.count <= ScsValues.httpHeadMaximumLength else { return .invalid }
      return .needMoreData
    }
    guard let request = ScsHttpRequest.parse(head: buffer[..<boundary.lowerBound]) else {
      return .invalid
    }
    guard (0...ScsValues.httpBodyMaximumLength).contains(request.bodyLength) else {
      return .invalid
    }
    let body = buffer[boundary.upperBound...]
    guard body.count >= request.bodyLength else { return .needMoreData }
    return .complete(
      ScsHttpExchange(request: request, body: Data(body.prefix(request.bodyLength))))
  }
}
