// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

/// Structured Web eID protocol error returned across the native bridge.
public struct WebEidError: Error, Codable, Equatable, Sendable {
  /// Machine-readable Web eID error code.
  public let code: WebEidErrorCode

  /// Human-readable diagnostic summary free of sensitive data.
  public let message: String

  /// Creates a Web eID protocol error.
  public init(code: WebEidErrorCode, message: String) {
    self.code = code
    self.message = message
  }

  /// Dictionary matching the `{ "error": { "code": ..., "message": ... } }`
  /// envelope expected by the Web eID background script.
  public func responseDictionary() -> [String: Any] {
    [
      "error": [
        "code": code.rawValue,
        "message": message,
      ]
    ]
  }
}
