// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CryptoKit
import Foundation
import os

/// The stateful SCS transaction flow (DVV SCS specification v1.3
/// §2.7): a signed `begin` establishes an encrypted channel, one
/// `execute` inside it produces the signature within the bounded TTL.
public final class ScsTransactionManager: Sendable {
  private let pending = OSAllocatedUnfairLock<ScsAgreedTransaction?>(initialState: nil)

  /// Creates a manager with no pending transaction.
  public init() {
    // Starts empty by definition: no transaction has begun.
  }

  private static func isExpired(_ state: ScsAgreedTransaction, at now: Date) -> Bool {
    now.timeIntervalSince(state.createdAt) > ScsValues.transactionTimeToLiveSeconds
      || now < state.createdAt.addingTimeInterval(-ScsValues.notBeforeClockSkewSeconds)
  }

  private static func compactJwsSegments(
    _ compactJws: Data
  ) -> Result<[String], ScsTransactionError> {
    guard let compact = String(data: compactJws, encoding: .utf8) else {
      return .failure(.badRequest("JWT body is not UTF-8"))
    }
    let segments = compact.components(separatedBy: ".")
    guard
      segments.count == ScsValues.jwsSegmentCount,
      segments.allSatisfy({ segment in !segment.isEmpty })
    else {
      return .failure(.badRequest("begin transaction must be a compact JWS"))
    }
    return .success(segments)
  }

  /// Drops any pending agreed transaction, called when the listener
  /// stops so no agreed key survives across disable and re-enable.
  public func clear() {
    pending.withLock { current in
      current = nil
    }
  }

  /// Handles the `begin` JWS: verifies it, agrees the transaction
  /// key, and answers the card-signed response JWT.
  public func begin(
    compactJws: Data,
    origin: String?,
    at now: Date,
    backend: any ScsSigningBackend
  ) -> Result<String, ScsTransactionError> {
    guard case .success(let requestOrigin) = ScsTransactionCodec.validatedOrigin(origin) else {
      return ScsTransactionCodec.validatedOrigin(origin)
    }
    let segments: [String]
    switch Self.compactJwsSegments(compactJws) {
    case .success(let parsed):
      segments = parsed

    case .failure(let error):
      return .failure(error)
    }
    guard hasAvailableSlot(at: now) else {
      return .failure(.forbidden("another signature request is already active"))
    }
    let outcome: ScsTransactionBegin.Outcome
    switch ScsTransactionBegin.perform(
      segments: segments, origin: requestOrigin, at: now, backend: backend)
    {
    case .success(let performed):
      outcome = performed

    case .failure(let error):
      return .failure(error)
    }
    guard storeAgreed(outcome.state, at: now) else {
      return .failure(.forbidden("another signature request became active"))
    }
    return .success(outcome.response)
  }

  /// Handles the `execute` JWE at the current wall-clock time.
  public func execute(
    compactJwe: Data,
    origin: String?,
    backend: any ScsSigningBackend
  ) -> Result<String, ScsTransactionError> {
    execute(compactJwe: compactJwe, origin: origin, at: Date(), backend: backend)
  }

  /// Handles the `execute` JWE at `now`, consuming and expiring the
  /// pending transaction slot either way.
  public func execute(
    compactJwe: Data,
    origin: String?,
    at now: Date,
    backend: any ScsSigningBackend
  ) -> Result<String, ScsTransactionError> {
    let requestOrigin: String
    switch ScsTransactionCodec.validatedOrigin(origin) {
    case .success(let validated):
      requestOrigin = validated

    case .failure(let error):
      return .failure(error)
    }
    guard
      let state = pending.withLock({ current in
        let taken = current
        current = nil
        return taken
      })
    else {
      return .failure(.badRequest("no active transaction"))
    }
    guard !Self.isExpired(state, at: now) else {
      return .failure(.badRequest("transaction expired"))
    }
    guard state.origin == requestOrigin else {
      return .failure(.forbidden("execute Origin does not match begin Origin"))
    }
    let payloadBytes: Data
    switch ScsJsonWebEncryption.decrypt(compact: compactJwe, key: state.key) {
    case .success(let decrypted):
      payloadBytes = decrypted

    case .failure(let error):
      return .failure(error)
    }
    guard
      let payload = try? JSONDecoder().decode(ScsExecuteDocument.self, from: payloadBytes)
    else {
      return .failure(.badRequest("execute payload is not valid JSON"))
    }
    return ScsTransactionExecution.respond(
      payload: payload, state: state, backend: backend)
  }

  private func hasAvailableSlot(at now: Date) -> Bool {
    pending.withLock { current in
      if let existing = current, Self.isExpired(existing, at: now) {
        current = nil
      }
      return current == nil
    }
  }

  private func storeAgreed(_ state: ScsAgreedTransaction, at now: Date) -> Bool {
    pending.withLock { current in
      if let existing = current, Self.isExpired(existing, at: now) {
        current = nil
      }
      guard current == nil else { return false }
      current = state
      return true
    }
  }
}
