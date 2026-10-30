// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation
import os

/// PIN 1 held for each card in the token extension, keyed by the full
/// ``ChipSerial``.
///
/// Each card has at most one value, in one of two states. A candidate is a
/// PIN the holder typed in the system sheet that the card has not verified
/// yet: CryptoTokenKit collects it before the field opens, and it is kept
/// across field loss and token recreation until VERIFY is attempted, its
/// sheet is cancelled, or the card is forgotten. Only one candidate exists
/// at a time; staging or asking about one card drops a candidate held for
/// any other. An accepted value is a PIN the card verified, held for silent
/// reuse only while ``Pin1Retention`` permits it (RAPP v26.10.29 section 11
/// item 2, FINEID S1 v4.2 section 3.5).
///
/// Values live only in zeroizing process memory and are never persisted.
/// The CryptoTokenKit ``TokenInstanceID`` keys nothing here.
public final class Pin1Memory: Sendable {
  // MARK: Nested Types

  /// A copy of a PIN taken before VERIFY consumes it, held as accepted
  /// only when committed after the card verified it.
  public struct Acceptance: Sendable {
    fileprivate let serial: ChipSerial
    fileprivate let digits: ZeroizingDigitStore
  }

  private enum State: Equatable {
    case candidate(operationID: UUID)
    case accepted
  }

  private struct Entry {
    let digits: ZeroizingDigitStore
    let state: State

    var isCandidate: Bool {
      if case .candidate = state { return true }
      return false
    }
  }

  // MARK: Static Properties

  /// The token extension's PIN 1 memory.
  public static let shared = Pin1Memory()

  // MARK: Properties

  private let entries = OSAllocatedUnfairLock<[ChipSerial: Entry]>(initialState: [:])

  // MARK: Lifecycle

  internal init() {
    // Starts empty: no PIN has been typed or accepted yet.
  }

  // MARK: Static Functions

  private static func dropCandidates(
    in entries: inout [ChipSerial: Entry],
    except serial: ChipSerial
  ) {
    entries = entries.filter { key, entry in
      key == serial || !entry.isCandidate
    }
  }

  // MARK: Functions

  /// Whether this card has a candidate or an accepted value.
  public func holdsValue(serial: ChipSerial) -> Bool {
    entries.withLock { entries in
      Self.dropCandidates(in: &entries, except: serial)
      return entries[serial] != nil
    }
  }

  /// Stages a typed, unverified PIN for this card, replacing its value.
  ///
  /// Returns false and stages nothing when the digits are not a PIN 1.
  @discardableResult
  public func stageCandidate(
    digits: String,
    serial: ChipSerial,
    operationID: UUID
  ) -> Bool {
    guard
      let store = CredentialDigits.validated(
        digits,
        minimumCount: Pin1.minimumDigitCount,
        maximumCount: Pin1.maximumDigitCount
      )
    else {
      return false
    }
    entries.withLock { entries in
      Self.dropCandidates(in: &entries, except: serial)
      entries[serial] = Entry(digits: store, state: .candidate(operationID: operationID))
    }
    return true
  }

  /// Drops the candidate the given sheet staged, if it is still held.
  public func cancelCandidate(operationID: UUID) {
    entries.withLock { entries in
      entries = entries.filter { _, entry in
        entry.state != .candidate(operationID: operationID)
      }
    }
  }

  /// A copy of this card's candidate, left in place until VERIFY decides it.
  public func checkoutCandidate(serial: ChipSerial) -> Pin1? {
    let copy: ZeroizingDigitStore? = entries.withLock { entries in
      Self.dropCandidates(in: &entries, except: serial)
      guard let entry = entries[serial], entry.isCandidate else { return nil }
      return ZeroizingDigitStore(bytes: entry.digits.bytes)
    }
    guard let copy else { return nil }
    return Pin1(owning: copy)
  }

  /// Drops this card's value when it is a candidate.
  public func clearCandidate(serial: ChipSerial) {
    entries.withLock { entries in
      if entries[serial]?.isCandidate == true {
        entries[serial] = nil
      }
    }
  }

  /// A copy of the PIN this card accepted, or nil when none is held.
  public func checkoutAccepted(serial: ChipSerial) -> Pin1? {
    let copy: ZeroizingDigitStore? = entries.withLock { entries in
      guard let entry = entries[serial], entry.state == .accepted else { return nil }
      return ZeroizingDigitStore(bytes: entry.digits.bytes)
    }
    guard let copy else { return nil }
    return Pin1(owning: copy)
  }

  /// Applies ``Pin1Retention`` to the probe that precedes a PIN-bearing
  /// command: drops this card's accepted value when the probe forbids
  /// holding, and returns whether holding is permitted.
  @discardableResult
  public func retain(after probe: RetryProbeOutcome, serial: ChipSerial) -> Bool {
    guard Pin1Retention.permitsHolding(after: probe) else {
      entries.withLock { entries in
        if entries[serial]?.state == .accepted {
          entries[serial] = nil
        }
      }
      return false
    }
    return true
  }

  /// Copies `pin` for acceptance after VERIFY, or nil when the probe
  /// before it forbids holding (``Pin1Retention``).
  public func acceptance(
    of pin: borrowing Pin1,
    serial: ChipSerial,
    after probe: RetryProbeOutcome
  ) -> Acceptance? {
    guard Pin1Retention.permitsHolding(after: probe) else { return nil }
    return Acceptance(serial: serial, digits: pin.cachedCopy())
  }

  /// Holds the value as accepted once the card verified it, replacing a
  /// candidate for the same card.
  public func commit(_ acceptance: Acceptance) {
    entries.withLock { entries in
      entries[acceptance.serial] = Entry(digits: acceptance.digits, state: .accepted)
    }
  }

  /// Drops this card's value, whatever its state.
  public func clear(serial: ChipSerial) {
    entries.withLock { entries in
      entries[serial] = nil
    }
  }

  /// Drops every value.
  public func clearAll() {
    entries.withLock { entries in
      entries.removeAll()
    }
  }
}
