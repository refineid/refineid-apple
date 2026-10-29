// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation
import os

/// Volatile process-level memory in the token extension for accepted PIN1.
///
/// Remembers the verified PIN1 bound to a physical card across token and session
/// recreation during the lifetime of the token extension process (RAPP
/// v26.10.29 §11 item 2). Survives normal NFC field expiry and slot state drops,
/// so that subsequent Safari client-certificate authentication requests do not
/// re-prompt the holder.
///
/// Cleared immediately upon:
/// - Explicit card rejection (SW 63Cx, SW 6983).
/// - Token revocation.
/// - The card's setup being forgotten.
///
/// Lives exclusively in zeroizing volatile memory; never written to the keychain or disk.
public final class VolatileAcceptedPin1: Sendable {
  // MARK: Nested Types

  /// Staged acceptance pending successful verification by the card.
  public struct PendingAcceptance: Sendable {
    internal let instanceID: CardInstanceIdentifier
    internal let store: ZeroizingDigitStore

    /// Commits the verified PIN1 to accepted memory.
    public func commit() {
      VolatileAcceptedPin1.shared.commit(self)
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
    // Starts empty: no card has accepted a PIN yet.
  }

  // MARK: Functions

  /// Whether an accepted PIN1 is available in memory for this card instance.
  public func hasPin(for instanceID: CardInstanceIdentifier) -> Bool {
    entries.withLock { $0[instanceID] != nil }
  }

  /// A reusable PIN1 for this card instance from memory, or nil when none was accepted.
  public func checkout(for instanceID: CardInstanceIdentifier) -> Pin1? {
    let store: ZeroizingDigitStore? = entries.withLock { entries in
      guard let entry = entries[instanceID] else {
        return nil
      }
      return ZeroizingDigitStore(bytes: entry.bytes)
    }
    guard let store else {
      return nil
    }
    return Pin1(owning: store)
  }

  /// Prepares to accept `pin` if and only if the card later accepts it.
  public func prepareAcceptance(
    of pin: borrowing Pin1,
    for instanceID: CardInstanceIdentifier
  ) -> PendingAcceptance {
    PendingAcceptance(instanceID: instanceID, store: pin.cachedCopy())
  }

  /// Commits a verified pending acceptance to memory.
  public func commit(_ pending: PendingAcceptance) {
    entries.withLock { entries in
      entries[pending.instanceID] = pending.store
    }
  }

  /// Stores a PIN1 only after the matching card has accepted it.
  public func store(_ pin: borrowing Pin1, for instanceID: CardInstanceIdentifier) {
    let digits = pin.cachedCopy()
    entries.withLock { entries in
      entries[instanceID] = digits
    }
  }

  /// Drops the accepted PIN for one card instance.
  public func clear(for instanceID: CardInstanceIdentifier) {
    entries.withLock { entries in
      entries[instanceID] = nil
    }
  }

  /// Drops all accepted PIN values.
  public func clearAll() {
    entries.withLock { entries in
      entries.removeAll()
    }
  }
}
