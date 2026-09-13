// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import os

/// PIN1 the named card has accepted, held by one live token.
///
/// Remembers the verified PIN entry bound to this live token.
///
/// When the card session is already in the verified state and has
/// valid checked-out PIN1 memory, subsequent signature operations
/// can reuse the verified state (FINEID S1 v4.2 §3.5). The memory
/// spares the holder from retyping while this token remains. The token
/// dies when the card or reader leaves, and the PIN dies with it.
///
/// Cannot lock a card because it only ever holds a PIN the card just
/// accepted, every reuse is bound to the full card serial, and the caller
/// obtains fresh PIN1 retry state before checkout. A value is removed on
/// the first confirmed card rejection.
///
/// Values live only in zeroizing memory. They are never persisted here.
public final class AcceptedPin1Memory: Sendable {
  /// One accepted PIN per physical card.
  private let entries = OSAllocatedUnfairLock<[TokenSerial: ZeroizingDigitStore]>(
    initialState: [:])

  /// Creates empty process memory.
  public init() {
    // Starts empty by definition: no card has accepted a PIN yet.
  }

  /// A reusable PIN1 for this exact card, or nil when none was accepted.
  public func checkout(serial: TokenSerial) -> Pin1? {
    let reusable: ZeroizingDigitStore? = entries.withLock { entries in
      guard let entry = entries[serial] else { return nil }
      return ZeroizingDigitStore(bytes: entry.bytes)
    }
    guard let reusable else { return nil }
    return Pin1(owning: reusable)
  }

  /// Stores a PIN1 only after this card accepted it.
  public func store(_ pin: borrowing Pin1, serial: TokenSerial) {
    let digits = pin.cachedCopy()
    entries.withLock { entries in
      entries[serial] = digits
    }
  }

  /// Drops the accepted PIN for one physical card.
  public func clear(serial: TokenSerial) {
    entries.withLock { entries in
      entries[serial] = nil
    }
  }

  /// Drops all accepted PIN values, for explicit process-state reset.
  public func clearAll() {
    entries.withLock { entries in
      entries.removeAll()
    }
  }
}
