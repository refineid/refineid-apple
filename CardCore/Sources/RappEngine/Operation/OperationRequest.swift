// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// One typed request, which lives inside the session that carried it (RAPP
/// v26.10.29 §8.1).
internal struct OperationRequest: Equatable {
  /// The lifetime a request that names none receives (§8.1 item 2).
  internal static let defaultLifetimeMilliseconds: UInt64 = 300_000

  /// Used once per session.
  internal let operationIdentifier: RappOperationIdentifier

  internal let profile: ProfileName

  /// Local receipt or creation time on the continuous clock, which advances
  /// through suspension (§8.1 item 2).
  ///
  /// Never sent.
  internal let localStartMilliseconds: UInt64

  /// Relative validity the peer sends, capped again by local policy.
  internal let expiresAfterMilliseconds: UInt64

  internal let operation: CardOperation

  internal init(
    operationIdentifier: RappOperationIdentifier,
    profile: ProfileName,
    localStartMilliseconds: UInt64,
    expiresAfterMilliseconds: UInt64,
    operation: CardOperation
  ) throws {
    self.operationIdentifier = operationIdentifier
    self.profile = profile
    self.localStartMilliseconds = localStartMilliseconds
    self.expiresAfterMilliseconds = expiresAfterMilliseconds
    self.operation = operation
    try validate()
  }

  /// Parses a received request.
  ///
  /// - Throws: ``OperationRequestRefusal`` when the request is well formed
  ///   but names a lifetime, profile, action or parameter this endpoint
  ///   cannot serve, and ``CardOperationError`` when it breaks the schema.
  internal static func from(
    wireBody: [String: WireValue],
    localStartMilliseconds: UInt64
  ) throws -> Self {
    var body = wireBody
    let decodedOperationIdentifier = try takeOperationIdentifier(&body, "operation_id")
    let profileName = try takeOperationText(&body, "profile")
    let action = try takeOperationText(&body, "action")
    let context = try takeOperationMap(&body, "context")
    let payload = try takeOperationMap(&body, "payload")
    var lifetime = defaultLifetimeMilliseconds
    if body["expires_after_ms"] != nil {
      lifetime = try takeOperationUnsigned(&body, "expires_after_ms")
    }
    guard body.isEmpty else { throw CardOperationError.unexpectedField }
    guard lifetime > 0 else {
      throw OperationRequestRefusal(
        operationIdentifier: decodedOperationIdentifier, error: .invalidLifetime)
    }
    do {
      guard let decodedProfile = ProfileName(rawValue: profileName) else {
        throw CardOperationError.unknownProfile
      }
      return try Self(
        operationIdentifier: decodedOperationIdentifier,
        profile: decodedProfile,
        localStartMilliseconds: localStartMilliseconds,
        expiresAfterMilliseconds: lifetime,
        operation: try CardOperation.from(action: action, context: context, payload: payload))
    } catch {
      throw OperationRequestRefusal(
        operationIdentifier: decodedOperationIdentifier, error: .unsupportedParameter)
    }
  }

  /// Rejects a request whose lifetime or profile do not agree.
  internal func validate() throws {
    guard expiresAfterMilliseconds > 0 else { throw CardOperationError.invalidLifetime }
    guard profile == operation.requiredProfile else {
      throw CardOperationError.profileActionMismatch
    }
    try operation.validate()
  }

  /// Local deadline on the continuous clock, shortened by this endpoint's
  /// own maximum.
  internal func localDeadlineMilliseconds(maximumLifetimeMilliseconds: UInt64) throws -> UInt64 {
    try validate()
    guard maximumLifetimeMilliseconds > 0 else { throw CardOperationError.invalidLifetime }
    let lifetime = min(expiresAfterMilliseconds, maximumLifetimeMilliseconds)
    let (deadline, overflowed) = localStartMilliseconds.addingReportingOverflow(lifetime)
    return overflowed ? UInt64.max : deadline
  }

  /// The exact `operation.request` body.
  internal func wireBody() -> [String: WireValue] {
    [
      "operation_id": .bytes(operationIdentifier.bytes),
      "profile": .text(profile.rawValue),
      "action": .text(operation.action),
      "expires_after_ms": .unsigned(expiresAfterMilliseconds),
      "context": .map(operation.context),
      "payload": .map(operation.payload),
    ]
  }
}
