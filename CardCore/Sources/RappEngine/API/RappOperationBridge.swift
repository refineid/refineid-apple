// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// The operations of one established session (RAPP v26.10.22 §8).
///
/// Every call answers with the bounded step the caller performs next. The
/// bridge decides what must happen; the caller performs it, so nothing here
/// touches a card, a transport, or a screen. The caller transports only
/// opaque sealed frames and never sees a decrypted message, a PIN, a CAN or
/// a pair key. Nothing of an operation outlives its session.
public final class RappOperationBridge: @unchecked Sendable {
  /// Which side of the pairing this bridge serves.
  internal enum Side {
    case proxy(ProxyOperationEngine)
    case requester(RequesterOperationEngine)
  }

  internal let lock = NSLock()
  internal let grantedProfiles: [ProfileName]
  internal let maximumLifetimeMilliseconds: UInt64
  internal var liveness: LivenessTracker
  internal var session: EstablishedSession
  internal var side: Side
  internal var closed = false

  internal init(
    session: EstablishedSession,
    grantedProfiles: [ProfileName],
    side: Side,
    maximumLifetimeMs: UInt64,
    nowMilliseconds: UInt64
  ) throws {
    guard maximumLifetimeMs > 0 else { throw RappBindingError.InvalidInput }
    self.session = session
    self.grantedProfiles = grantedProfiles
    self.side = side
    self.maximumLifetimeMilliseconds = maximumLifetimeMs
    self.liveness = LivenessTracker(nowMilliseconds: nowMilliseconds)
  }

  /// Takes the established session as the requester.
  ///
  /// - Throws: ``RappBindingError/WrongPhase`` when the session is not
  ///   established, and ``RappBindingError/InvalidInput`` on a zero
  ///   lifetime.
  public static func beginRequester(
    session: RappSessionBridge, maximumLifetimeMs: UInt64, nowMs: UInt64
  ) throws -> RappOperationBridge {
    let established = try session.takeEstablished()
    return try RappOperationBridge(
      session: established.session,
      grantedProfiles: established.pair.profiles,
      side: .requester(RequesterOperationEngine()),
      maximumLifetimeMs: maximumLifetimeMs,
      nowMilliseconds: nowMs)
  }

  /// Takes the established session as the custodian.
  ///
  /// Report the card with ``reportCardStatus(authenticationCertificate:)``
  /// right after, so `card.status` follows `session.ready` (§8.4).
  ///
  /// - Throws: ``RappBindingError/WrongPhase`` when the session is not
  /// established, and ``RappBindingError/InvalidInput`` on a zero
  /// lifetime.
  public static func beginProxy(
    session: RappSessionBridge, maximumLifetimeMs: UInt64, nowMs: UInt64
  ) throws -> RappOperationBridge {
    let established = try session.takeEstablished()
    return try RappOperationBridge(
      session: established.session,
      grantedProfiles: established.pair.profiles,
      side: .proxy(ProxyOperationEngine(grantedProfiles: established.pair.profiles)),
      maximumLifetimeMs: maximumLifetimeMs,
      nowMilliseconds: nowMs)
  }
}
