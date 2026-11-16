// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// Incremental assembly of one SCS HTTP exchange from transport bytes.
///
/// The transport hands over whatever it has read so far; assembly
/// answers whether the buffer already holds the complete request. Both
/// head and body are strictly bounded (64 KiB head, 100 MiB body per
/// DVV SCS specification v1.3 §2.1) and trailing pipelined bytes after
/// `Content-Length` are refused.
public enum ScsHttpAssembly: Equatable, Sendable {
  /// The buffer holds a complete request head and body.
  case complete(ScsHttpExchange)

  /// The buffer can never become a valid request; close the
  /// connection.
  case invalid

  /// The buffer is a valid prefix; read more bytes.
  case needMoreData

  /// Whether appending `incomingCount` bytes to `bufferedCount` would
  /// exceed the combined HTTP head plus 100 MiB body ceiling.
  public static func exceedsReceiveCeiling(
    bufferedCount: Int,
    incomingCount: Int
  ) -> Bool {
    guard bufferedCount >= 0, incomingCount >= 0 else { return true }
    let maximumTotal = ScsValues.httpHeadMaximumLength + ScsValues.httpBodyMaximumLength
    let (sum, overflow) = bufferedCount.addingReportingOverflow(incomingCount)
    return overflow || sum > maximumTotal
  }

  /// Classifies the buffer as read so far.
  public static func assemble(buffer: Data) -> Self {
    let headEnd = Data("\r\n\r\n".utf8)
    guard let boundary = buffer.range(of: headEnd) else {
      guard buffer.count <= ScsValues.httpHeadMaximumLength else { return .invalid }
      return .needMoreData
    }
    let headLength = buffer.distance(from: buffer.startIndex, to: boundary.lowerBound)
    guard headLength <= ScsValues.httpHeadMaximumLength else { return .invalid }
    guard let request = ScsHttpRequest.parse(head: buffer[..<boundary.lowerBound]) else {
      return .invalid
    }
    guard (0...ScsValues.httpBodyMaximumLength).contains(request.bodyLength) else {
      return .invalid
    }
    let body = buffer[boundary.upperBound...]
    if body.count > request.bodyLength {
      return .invalid
    }
    guard body.count == request.bodyLength else { return .needMoreData }
    return .complete(ScsHttpExchange(request: request, body: Data(body)))
  }
}
