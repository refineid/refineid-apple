// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(iOS) && REFINEID_LOCAL_CARD

  import Foundation
  import RappEngine

  /// PIN 1 the holder entered on this phone, bound to the card it was
  /// entered for: one the card accepted, or one no card ever received
  /// because the card did not come (RAPP v26.10.29 §8.4 item 1, §11 item 2).
  ///
  /// Held only in this process's memory, never in storage, so it ends with
  /// the process and with a restart. It also ends when the card leaves the
  /// reader or the holder removes it from the phone, when another card
  /// takes its place, when the card refuses it, and when the holder
  /// forgets the card's setup. While it is held, a browser authentication
  /// runs with no prompt.
  @MainActor
  internal final class HeldPin1 {
    /// One held value and the card it belongs to.
    private struct Entry {
      let digits: String
      let card: RappCertificateFingerprint
    }

    internal static let shared = HeldPin1()

    private var entry: Entry?

    private init() {
      // singleton
    }

    /// The PIN 1 held for `card`, the card the phone holds now.
    ///
    /// Nil when none is held for it, or the phone holds no card it can name;
    /// a value held for another card is forgotten.
    internal func current(card: RappCertificateFingerprint?) -> String? {
      guard let entry else { return nil }
      guard entry.card == card else {
        clear()
        return nil
      }
      return entry.digits
    }

    /// Holds a PIN 1 that `card` has just accepted.
    internal func hold(_ pin1: String, card: RappCertificateFingerprint) {
      guard !pin1.isEmpty else {
        clear()
        return
      }
      entry = Entry(digits: pin1, card: card)
    }

    /// Forgets the held PIN 1 unless it belongs to `card`, the card the
    /// phone holds now.
    internal func keep(onlyFor card: RappCertificateFingerprint?) {
      if entry?.card != card {
        entry = nil
      }
    }

    /// Forgets the held PIN 1.
    internal func clear() {
      entry = nil
    }
  }

#endif
