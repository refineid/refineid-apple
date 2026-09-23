// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation
import os

/// Volatile process-level memory in the token extension for accepted PIN1.
///
/// Remembers the verified PIN1 bound to a physical card across token and session
/// recreation during the lifetime of the token extension process.
/// Survives normal NFC field expiry and slot state drops, so that subsequent Safari
/// client-certificate authentication requests do not re-prompt the user.
///
/// Cleared immediately upon:
/// - Explicit card rejection (SW 63Cx, SW 6983).
/// - Token revocation.
/// - Credential forget/reset.
/// - Disabling the on-demand PIN experiment.
///
/// Lives exclusively in zeroizing volatile memory; never written to the keychain or disk.
public final class VolatileAcceptedPin1: Sendable {
  // MARK: Nested Types

  /// Staged acceptance pending successful verification by the card.
  public struct PendingAcceptance: Sendable {
    internal let instanceID: CardInstanceIdentifier
    internal let store: ZeroizingDigitStore

    /// Commits the verified PIN1 to accepted memory and persistent credential store.
    public func commit() {
      VolatileAcceptedPin1.shared.commit(self)
      if let digits = String(bytes: store.bytes, encoding: .utf8) {
        CardCredentialStore.save(pin1: digits)
      }
    }
  }

  // MARK: Static Properties

  /// Shared volatile accepted PIN1 store for the token extension process.
  public static let shared = VolatileAcceptedPin1()

  // MARK: Properties

  private let entries = OSAllocatedUnfairLock<[CardInstanceIdentifier: ZeroizingDigitStore]>(
    initialState: [:]
  )

  // MARK: Lifecycle

  internal init() {
    // Shared in-process accepted PIN store backed by CardCredentialStore.
  }

  // MARK: Functions

  /// Whether an accepted PIN1 is available for this card instance under the active experiment.
  public func hasPin(for instanceID: CardInstanceIdentifier) -> Bool {
    guard OnDemandPinExperiment.isEnabled else {
      return false
    }
    if CardCredentialStore.contents().hasPin1 {
      return true
    }
    return entries.withLock { $0[instanceID] != nil }
  }

  /// A reusable PIN1 for this card instance, or nil when none was accepted or experiment is disabled.
  public func checkout(for instanceID: CardInstanceIdentifier) -> Pin1? {
    guard OnDemandPinExperiment.isEnabled else {
      return nil
    }
    let store: ZeroizingDigitStore? = entries.withLock { entries in
      guard let entry = entries[instanceID] else {
        return nil
      }
      return ZeroizingDigitStore(bytes: entry.bytes)
    }
    if let store {
      return Pin1(owning: store)
    }
    return CardCredentialStore.pin1()
  }

  /// Prepares to accept `pin` if and only if the card later accepts it.
  public func prepareAcceptance(
    of pin: borrowing Pin1,
    for instanceID: CardInstanceIdentifier
  ) -> PendingAcceptance? {
    guard OnDemandPinExperiment.isEnabled else {
      return nil
    }
    return PendingAcceptance(instanceID: instanceID, store: pin.cachedCopy())
  }

  /// Commits a verified pending acceptance to memory.
  public func commit(_ pending: PendingAcceptance) {
    guard OnDemandPinExperiment.isEnabled else {
      return
    }
    entries.withLock { entries in
      entries[pending.instanceID] = pending.store
    }
  }

  /// Stores a PIN1 only after the matching card has accepted it.
  public func store(_ pin: borrowing Pin1, for instanceID: CardInstanceIdentifier) {
    guard OnDemandPinExperiment.isEnabled else {
      return
    }
    let digits = pin.cachedCopy()
    entries.withLock { entries in
      entries[instanceID] = digits
    }
    if let digitString = String(bytes: digits.bytes, encoding: .utf8) {
      CardCredentialStore.save(pin1: digitString)
    }
  }

  /// Drops the accepted PIN for one card instance.
  public func clear(for instanceID: CardInstanceIdentifier) {
    entries.withLock { entries in
      entries[instanceID] = nil
    }
    CardCredentialStore.forgetPin1()
  }

  /// Drops all accepted PIN values.
  public func clearAll() {
    entries.withLock { entries in
      entries.removeAll()
    }
    CardCredentialStore.forgetPin1()
  }
}
