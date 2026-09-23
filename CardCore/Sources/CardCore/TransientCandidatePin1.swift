// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// Volatile, card-bound store for an unverified candidate PIN1 entered in native secure UI.
///
/// Holds the user-entered candidate PIN across pre-VERIFY NFC field loss and token/session
/// recreation until:
/// 1. Card verification is attempted (at which point it is cleared or promoted).
/// 2. User cancels or dismisses the matching operation (tied to `operationID`).
/// 3. The card explicitly rejects the PIN or an ambiguous failure occurs during transmission.
/// 4. A different card is presented (mismatch).
/// 5. The experiment is disabled or credentials are forgotten.
///
/// Lives purely in volatile process memory with zeroization upon deallocation.
public final class TransientCandidatePin1: @unchecked Sendable {
  // MARK: Nested Types

  private struct Entry {
    let instanceID: CardInstanceIdentifier
    let store: ZeroizingDigitStore
    let operationID: UUID
    let correlationID: String
  }

  // MARK: Static Properties

  /// Shared singleton candidate store for the token extension process.
  public static let shared = TransientCandidatePin1()

  // MARK: Properties

  private let lock = NSLock()
  private var pending: Entry?

  // MARK: Lifecycle

  internal init() {
    // Shared volatile in-process candidate store.
  }

  // MARK: Functions

  /// Stages an unverified candidate PIN for card-bound checkout by a signing session.
  @discardableResult
  public func stage(
    digits: String,
    for instanceID: CardInstanceIdentifier,
    operationID: UUID,
    correlationID: String
  ) -> Bool {
    guard OnDemandPinExperiment.isEnabled else {
      return false
    }
    guard
      let digitStore = CredentialDigits.validated(
        digits,
        minimumCount: Pin1.minimumDigitCount,
        maximumCount: Pin1.maximumDigitCount
      )
    else {
      return false
    }
    lock.lock()
    defer { lock.unlock() }
    pending = Entry(
      instanceID: instanceID,
      store: digitStore,
      operationID: operationID,
      correlationID: correlationID
    )
    return true
  }

  /// Whether a valid candidate is pending for this card instance.
  public func hasPending(for instanceID: CardInstanceIdentifier) -> Bool {
    guard OnDemandPinExperiment.isEnabled else {
      lock.lock()
      pending = nil
      lock.unlock()
      return false
    }
    lock.lock()
    defer { lock.unlock() }
    guard let current = pending else {
      return false
    }
    guard current.instanceID == instanceID else {
      pending = nil
      return false
    }
    return true
  }

  /// Checks out a copy of the candidate PIN without clearing it before VERIFY.
  ///
  /// Returns nil if no candidate exists or if the card does not match.
  /// On card mismatch, immediately clears the pending candidate to prevent cross-card leakage.
  public func checkout(for instanceID: CardInstanceIdentifier) -> Pin1? {
    guard OnDemandPinExperiment.isEnabled else {
      lock.lock()
      pending = nil
      lock.unlock()
      return nil
    }
    lock.lock()
    defer { lock.unlock() }
    guard let current = pending else {
      return nil
    }
    guard current.instanceID == instanceID else {
      pending = nil
      return nil
    }
    let store = ZeroizingDigitStore(bytes: current.store.bytes)
    return Pin1(owning: store)
  }

  /// Explicitly invalidates the candidate if it was staged by the specified operation.
  public func cancel(operationID: UUID) {
    lock.lock()
    defer { lock.unlock() }
    if pending?.operationID == operationID {
      pending = nil
    }
  }

  /// Clears any pending candidate bound to this card instance.
  public func clear(for instanceID: CardInstanceIdentifier) {
    lock.lock()
    defer { lock.unlock() }
    if pending?.instanceID == instanceID {
      pending = nil
    }
  }

  /// Clears and zeroizes any pending candidate unconditionally.
  public func clearAll() {
    lock.lock()
    defer { lock.unlock() }
    pending = nil
  }
}
