// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import RappEngine

/// How a requester asks its user for the paired phone's card (RAPP
/// v26.10.29 §8.4 item 6, STPA CC-82).
///
/// The phone's card reader is named only while the phone reports no card
/// and a reader attached; otherwise the card is to be presented to the
/// phone itself.
internal enum PhoneCardRequest: Equatable, Sendable {
  /// Insert the card into the phone's card reader.
  case insertIntoPhoneReader
  /// Place the card on the phone.
  case placeOnPhone

  /// The request the phone's latest `card.status` calls for; nil while the
  /// phone holds a card, or before any session reported.
  internal init?(_ status: RappCardStatus?) {
    guard let status, status.card == .absent else { return nil }
    switch status.reader {
    case .attached:
      self = .insertIntoPhoneReader

    case .absent:
      self = .placeOnPhone
    }
  }
}
