// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import os

/// PIN 1 the holder entered, bound to the card that accepted it while
/// ``Pin1Retention`` permits holding (RAPP v26.11.8 section 8.4 item 1,
/// section 11 item 2; FINEID S1 v4.2 section 3.5).
///
/// `Card` names the card; the phone binds the value to the card's
/// certificate fingerprint. Holding starts only when the card accepted the
/// PIN after a pre-VERIFY probe at the five-try limit or verified, and any
/// other probe reading or failed counter read clears what is held at once.
/// The value also ends when another card, or no card, is named in its place,
/// when the card refuses it, and when the holder forgets everything. The
/// owner keeps it in memory only, never in storage; the digits live only in
/// the entry's zeroizing store.
public struct CardBoundPin1<Card: Equatable & Sendable>: Sendable {
  /// Thread-safe zeroizing store so card-worker threads can clear a held
  /// value the moment a non-pristine or throwing counter read is observed,
  /// and reject settlements that raced a forget or card removal.
  public final class Vault: Sendable {
    private let state = OSAllocatedUnfairLock<(bound: CardBoundPin1<Card>, epoch: UInt64)>(
      initialState: (bound: CardBoundPin1<Card>(), epoch: 0)
    )

    /// The custody epoch before an operation starts, so a settlement drops a
    /// late accept when the holder forgot everything or the card left while
    /// the operation ran.
    public var epoch: UInt64 {
      state.withLock { $0.epoch }
    }

    /// Holds nothing.
    public init() {
      // Starts empty: no card has been given a PIN 1 yet.
    }

    /// The PIN 1 held for `card`, the card present now.
    public func current(card: Card?) -> Pin1Entry? {
      state.withLock { $0.bound.current(card: card) }
    }

    /// Holds `pin1` for `card`, replacing any value held before.
    public func hold(_ pin1: Pin1Entry, card: Card) {
      state.withLock { $0.bound.hold(pin1, card: card) }
    }

    /// Forgets the held value unless it belongs to `card`, advancing the
    /// custody epoch when it drops an entry or sees no card.
    public func keep(onlyFor card: Card?) {
      state.withLock { state in
        let hadEntry = state.bound.entry != nil
        state.bound.keep(onlyFor: card)
        if card == nil || (hadEntry && state.bound.entry == nil) {
          state.epoch &+= 1
        }
      }
    }

    /// Applies ``Pin1Retention`` to the probe that precedes a PIN-bearing
    /// command, forgetting the held value immediately when `probe` forbids
    /// holding.
    @discardableResult
    public func retain(after probe: RetryProbeOutcome) -> Bool {
      state.withLock { $0.bound.retain(after: probe) }
    }

    /// Settles the held value after one PIN 1 operation.
    ///
    /// When `startingEpoch` is supplied and a forget or card removal
    /// advanced the custody epoch meanwhile, an `.accepted` settlement holds
    /// nothing rather than reviving custody after the reset.
    public func settle(_ settlement: Settlement, startingEpoch: UInt64? = nil) {
      state.withLock { state in
        if case .accepted = settlement,
          let startingEpoch,
          startingEpoch != state.epoch
        {
          return
        }
        state.bound.settle(settlement)
      }
    }

    /// Forgets the held value and advances the custody epoch.
    public func clear() {
      state.withLock { state in
        state.bound.clear()
        state.epoch &+= 1
      }
    }
  }

  /// What one PIN 1 operation settles on the held value.
  public enum Settlement: Sendable {
    /// The card accepted a typed `pin1` for `card` after `preVerifyProbe`.
    case accepted(Pin1Entry, preVerifyProbe: RetryProbeOutcome, card: Card?)

    /// No card was reached before any counter read; nothing new is held.
    case cardUnavailable

    /// The card refused PIN 1, or a pre-VERIFY counter read failed.
    case clear

    /// A pre-VERIFY counter read reported `RetryProbeOutcome`.
    case probed(RetryProbeOutcome)

    /// No counter or credential refusal changed what is held.
    case unchanged
  }

  /// One held value and the card it belongs to.
  private struct Entry: Sendable {
    let pin1: Pin1Entry
    let card: Card
  }

  private var entry: Entry?

  /// Holds nothing.
  public init() {
    // Starts empty: no card has been given a PIN 1 yet.
  }

  /// The PIN 1 held for `card`, the card present now.
  ///
  /// Nil when none is held for it, or no card can be named; a value held
  /// for another card is forgotten.
  public mutating func current(card: Card?) -> Pin1Entry? {
    guard let entry else { return nil }
    guard entry.card == card else {
      clear()
      return nil
    }
    return entry.pin1
  }

  /// Holds `pin1` for `card`, replacing any value held before.
  public mutating func hold(_ pin1: Pin1Entry, card: Card) {
    entry = Entry(pin1: pin1, card: card)
  }

  /// Forgets the held value unless it belongs to `card`, the card present
  /// now.
  public mutating func keep(onlyFor card: Card?) {
    if entry?.card != card {
      entry = nil
    }
  }

  /// Applies ``Pin1Retention`` to the probe that precedes a PIN-bearing
  /// command: forgets the held value when `probe` forbids holding, and
  /// returns whether holding is permitted.
  @discardableResult
  public mutating func retain(after probe: RetryProbeOutcome) -> Bool {
    guard Pin1Retention.permitsHolding(after: probe) else {
      clear()
      return false
    }
    return true
  }

  /// Settles the held value after one PIN 1 operation.
  public mutating func settle(_ settlement: Settlement) {
    switch settlement {
    case .accepted(let pin1, let preVerifyProbe, let card):
      guard retain(after: preVerifyProbe), let card else {
        clear()
        return
      }
      hold(pin1, card: card)

    case .cardUnavailable, .unchanged:
      break

    case .clear:
      clear()

    case .probed(let probe):
      retain(after: probe)
    }
  }

  /// Forgets the held value.
  public mutating func clear() {
    entry = nil
  }
}
