// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// One Web eID response handed from `RefineID.app` back to the Safari Web
/// Extension through the shared App Group bridge.
public struct WebEidBridgeResponse: Codable, Equatable, Sendable {
  /// Correlation nonce matching the originating request.
  public let nonce: UUID

  /// Structured success payload, when the command succeeded.
  public let payload: WebEidResponsePayload?

  /// Structured protocol error, when the command failed or was cancelled.
  public let error: WebEidError?

  /// Creates a successful bridge response for `nonce`.
  public init(nonce: UUID, payload: WebEidResponsePayload) {
    self.nonce = nonce
    self.payload = payload
    self.error = nil
  }

  /// Creates an error bridge response for `nonce`.
  public init(nonce: UUID, error: WebEidError) {
    self.nonce = nonce
    self.payload = nil
    self.error = error
  }

  /// Plain dictionary returned through `SFExtensionMessageKey`.
  public func toExtensionDictionary() -> [String: Any] {
    if let payload {
      return payload.toDictionary()
    }
    let resolvedError =
      error
      ?? WebEidError(
        code: .nativeFatal,
        message: "Empty Web eID bridge response"
      )
    return resolvedError.responseDictionary()
  }
}
