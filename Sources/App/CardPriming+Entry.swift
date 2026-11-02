// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if REFINEID_LOCAL_CARD

  import CardCore
  import Foundation

  /// What the holder typed into the setup entry, and what it becomes once
  /// the card on the antenna has said what it is.
  extension CardPriming {
    /// The setup entry "Card Access Number (CAN)": four to twelve digits,
    /// a secret until the card's first answer names its kind.
    ///
    /// On a personal card it must be the six printed digits, and becomes a
    /// ``CardAccessNumber``. On an organization card it is PIN 1, which
    /// opens that card's PACE, and becomes a ``Pin1Entry``. Nothing reads
    /// the digits before then: the type reflects as nothing and offers no
    /// other way to them.
    internal struct SetupEntry: Sendable, CustomReflectable {
      /// The shortest entry: an organization card's shortest PIN 1.
      internal static let minimumDigitCount = Pin1.minimumDigitCount

      /// The longest entry: an organization card's longest PIN 1.
      internal static let maximumDigitCount = Pin1.maximumDigitCount

      /// The digits as typed.
      private let digits: String

      /// An empty mirror: reflection never reaches the digits.
      internal var customMirror: Mirror {
        Mirror(self, children: [])
      }

      /// Four to twelve ASCII digits, or nil.
      internal init?(digits: String) {
        let asciiDigits = UInt8(ascii: "0")...UInt8(ascii: "9")
        guard
          (Self.minimumDigitCount...Self.maximumDigitCount).contains(digits.utf8.count),
          digits.utf8.allSatisfy({ asciiDigits.contains($0) })
        else {
          return nil
        }
        self.digits = digits
      }

      /// The card access number a personal card opens with: exactly the
      /// six printed digits, or nil, and then no PACE is run.
      internal func personalAccessNumber() -> ProvenAccessNumber? {
        CardAccessNumber(digits: digits).map { number in
          ProvenAccessNumber(value: number, digits: digits)
        }
      }

      /// The PIN 1 an organization card opens with.
      internal func organizationPin1() -> Pin1Entry? {
        Pin1Entry(digits: digits)
      }
    }

    /// The kind of card a hold found on the antenna, written by the card
    /// queue and read when the hold ends.
    internal final class FoundKind: @unchecked Sendable {
      private let lock = NSLock()
      private var kind: ContactlessCardKind?

      /// What the card's first answer named; nil when no card answered.
      internal var value: ContactlessCardKind? {
        lock.withLock { kind }
      }

      /// Records what the card's first answer named.
      internal func record(_ found: ContactlessCardKind) {
        lock.withLock { kind = found }
      }
    }
  }

#endif
