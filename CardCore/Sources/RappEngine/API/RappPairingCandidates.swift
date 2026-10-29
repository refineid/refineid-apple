// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// The custodians in pairing mode a requester tries with one typed code
/// (RAPP v26.10.29 §4.2, "Trying Each Custodian in Pairing Mode").
///
/// The platform creates one per submitted code, reports every endpoint
/// discovery finds in pairing mode by its own name for it (a service
/// instance, a peripheral identifier), opens the endpoints the ledger hands
/// out one at a time, and reports how each connection ended. A custodian
/// that answers busy is handed out again after its wait.
public final class RappPairingCandidates<Endpoint: Equatable & Sendable>: @unchecked Sendable {
  private let lock = NSLock()
  private var candidates = PairingCandidates<Endpoint>()

  /// The ledger of a code the user has just submitted.
  public init() {
    // Nothing found, opened or tried yet.
  }

  /// Records an endpoint discovery found in pairing mode: a `mode=pairing`
  /// service instance, or a BLE peripheral of the RAPP service.
  public func found(_ endpoint: Endpoint) {
    locked { $0.found(endpoint) }
  }

  /// The next endpoint to open a pairing connection to at the platform's
  /// monotonic `nowMonotonicMs`: one not yet opened, otherwise one that
  /// answered busy and whose wait has passed.
  ///
  /// When only endpoints still waiting out a busy answer are left, it names
  /// the earliest time to ask again; the platform waits quietly and asks
  /// then.
  ///
  /// - Throws: ``RappBindingError/WrongPhase`` while a pairing connection is
  ///   open or once the code is accepted or refused.
  public func nextEndpoint(nowMonotonicMs: UInt64) throws -> RappNextEndpoint<Endpoint> {
    try locked { candidates in
      do {
        return RappNextEndpoint(try candidates.nextEndpoint(nowMilliseconds: nowMonotonicMs))
      } catch {
        throw RappBindingError.WrongPhase
      }
    }
  }

  /// Admits the offer `bridge` holds, read over the open connection.
  ///
  /// Called before CPace step 1. Returns false when CPace already ran on
  /// this offer with the code, the same custodian found on another
  /// transport: the caller closes the connection without CPace and calls
  /// ``closed()``.
  ///
  /// - Throws: ``RappBindingError/WrongPhase`` when `bridge` is not a
  ///   requester's offer awaiting CPace, or no connection awaits an offer.
  public func beginTry(_ bridge: RappPairingBridge) throws -> Bool {
    guard let offer = bridge.requesterOfferAwaitingCpace() else {
      throw RappBindingError.WrongPhase
    }
    return try locked { candidates in
      do {
        try candidates.beginTry(offer)
        return true
      } catch CandidateError.offerAlreadyTried {
        return false
      } catch {
        throw RappBindingError.WrongPhase
      }
    }
  }

  /// The open connection closed without its custodian taking the code:
  /// refused or closed, no offer or one the requester rejects or already
  /// tried, no CPace step 2 within the attempt deadline, or a `T_B` that did
  /// not verify.
  ///
  /// `remoteUseAvailable` says whether the requester's remote use is on and
  /// no card is in a reader attached to it; without it no further custodian
  /// is tried and the answer is ``RappNextCandidate/interrupted``, unless
  /// every custodian tried already refused the code (hierarchy
  /// specification §5.2).
  ///
  /// - Throws: ``RappBindingError/WrongPhase`` when no connection is open or
  ///   the code is already accepted or refused.
  public func closed(remoteUseAvailable: Bool) throws -> RappNextCandidate {
    try locked { candidates in
      do {
        return RappNextCandidate(
          try candidates.closed(), remoteUseAvailable: remoteUseAvailable)
      } catch {
        throw RappBindingError.WrongPhase
      }
    }
  }

  /// The open connection's custodian answered `pairing-busy` at the
  /// platform's monotonic `nowMonotonicMs`, asking for a wait of
  /// `retryAfterMs`.
  ///
  /// The wait is the value ``rappPairingBusyRetryAfterMs(_:)`` read from its
  /// bootstrap or from the frame in place of CPace step 2, or the value
  /// ``rappRefusedAttemptRetryAfterMs(bootstrap:transportProfile:)`` read
  /// after a BLE step 1 the custodian refused (RAPP v26.10.29 §4.2, "Busy
  /// Refusal"). The endpoint is opened again after its wait and after every
  /// endpoint not yet opened; nothing is shown to the user.
  /// `remoteUseAvailable` is read as in ``closed(remoteUseAvailable:)``.
  ///
  /// - Throws: ``RappBindingError/InvalidInput`` for a wait beyond the
  ///   schema's greatest, and ``RappBindingError/WrongPhase`` when no
  ///   connection is open or the code is already accepted or refused.
  public func busy(
    retryAfterMs: UInt64, nowMonotonicMs: UInt64, remoteUseAvailable: Bool
  ) throws -> RappNextCandidate {
    guard retryAfterMs <= PairingBusy.maximumRetryAfterMilliseconds else {
      throw RappBindingError.InvalidInput
    }
    return try locked { candidates in
      do {
        return RappNextCandidate(
          try candidates.busy(
            retryAfterMilliseconds: retryAfterMs, nowMilliseconds: nowMonotonicMs),
          remoteUseAvailable: remoteUseAvailable)
      } catch {
        throw RappBindingError.WrongPhase
      }
    }
  }

  /// The custodian tried proved it holds the code: its `T_B` verified.
  ///
  /// - Throws: ``RappBindingError/WrongPhase`` when no CPace runs.
  public func accepted() throws {
    try locked { candidates in
      do {
        try candidates.accepted()
      } catch {
        throw RappBindingError.WrongPhase
      }
    }
  }

  private func locked<Value>(
    _ body: (inout PairingCandidates<Endpoint>) throws -> Value
  ) rethrows -> Value {
    lock.lock()
    defer { lock.unlock() }
    return try body(&candidates)
  }
}
