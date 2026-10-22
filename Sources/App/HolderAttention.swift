// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// Whether a card command needs the holder to bring the app forward first.
///
/// The phone may serve from the background over Bluetooth, but Core NFC
/// opens a reader session only for an app in the foreground: a command on
/// the near-field card from the background first summons the holder with a
/// notification and waits for the app to become active. A card in a reader
/// needs no screen. A PIN prompt posts its own notification and is not
/// decided here: entering the PIN is the consent (RAPP v26.10.22 §8.2
/// item 3).
internal enum HolderAttention: Equatable, Sendable {
  /// The card can be commanded now.
  case proceed
  /// The holder must bring the app forward before the card is commanded.
  case summon

  /// Where the card the command goes to sits.
  internal enum CardSource: Equatable, Sendable {
    case nearField
    case reader
  }

  /// What a command on the card in `source` needs while the app is active
  /// or not.
  internal static func needed(for source: CardSource, appActive: Bool) -> Self {
    switch source {
    case .reader:
      .proceed

    case .nearField:
      appActive ? .proceed : .summon
    }
  }
}
