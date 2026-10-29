// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// Whether a card command needs the holder to bring the app forward first.
///
/// The phone may serve from the background over Bluetooth, but the system
/// opens a near field only for an app in the foreground: a command on the
/// near-field card from the background first summons the holder with a
/// notification and waits for the app to become active. A warm near field
/// the app opened in the foreground needs no new field, so a command on it
/// runs while its system sheet keeps the app inactive. A card in a reader
/// needs no screen. A PIN prompt posts its own notification and is not
/// decided here: entering the PIN is the consent (RAPP v26.10.29 §8.2
/// item 3).
internal enum HolderAttention: Equatable, Sendable {
  /// The card can be commanded now.
  case proceed
  /// The holder must bring the app forward before the card is commanded.
  case summon

  /// Where the app is.
  internal enum AppState: Equatable, Sendable {
    /// On screen and taking input.
    case active

    /// Not on screen.
    case background

    /// On screen behind a system sheet or overlay.
    case inactive
  }

  /// Where the card the command goes to sits.
  internal enum CardSource: Equatable, Sendable {
    case nearField
    case reader
  }

  /// What a command on the card in `source` needs while the app is in
  /// `app`, with a warm near field open or not.
  internal static func needed(
    for source: CardSource,
    app: AppState,
    fieldWarm: Bool
  ) -> Self {
    switch (source, app) {
    case (.reader, _), (.nearField, .active):
      .proceed

    case (.nearField, .inactive):
      fieldWarm ? .proceed : .summon

    case (.nearField, .background):
      .summon
    }
  }
}
