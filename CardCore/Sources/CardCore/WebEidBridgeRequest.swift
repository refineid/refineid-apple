// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// One Web eID request handed from the Safari Web Extension to `RefineID.app`
/// through the shared App Group bridge.
///
/// Carries only public protocol inputs (origin, challenge nonce, or document
/// hash and signing certificate); credentials never cross this boundary.
public struct WebEidBridgeRequest: Codable, Equatable, Sendable {
  /// Unique correlation nonce for pairing with a response file.
  public let nonce: UUID

  /// Timestamp at which the extension enqueued the request.
  public let createdAt: Date

  /// Absolute deadline after which the request is expired and must not be
  /// executed or answered.
  public let expiresAt: Date

  /// Validated Web eID command to execute.
  public let command: WebEidCommand

  /// Creates a bridge request envelope with an explicit deadline.
  public init(nonce: UUID, createdAt: Date, expiresAt: Date, command: WebEidCommand) {
    self.nonce = nonce
    self.createdAt = createdAt
    self.expiresAt = expiresAt
    self.command = command
  }
}
