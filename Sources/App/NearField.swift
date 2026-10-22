// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// One near field the phone holds open: the system slot with the card in
/// it, the sheet the holder reads while it is up, and the card session
/// with its PACE channel prepared on it.
///
/// ``WarmNearField`` decides when a field opens, is reused and ends; this
/// is what it asks of the platform.
internal protocol NearField: AnyObject, Sendable {
  /// The card's exclusive session with PACE done and the application
  /// selected.
  associatedtype Channel: Sendable

  /// Whether the slot holds a valid card right now.
  var holdsValidCard: Bool { get }

  /// Whether the slot is gone: the card left, the holder closed the sheet,
  /// or the platform ended the field.
  var isMissing: Bool { get }

  /// The slot's state, named for a trace.
  var stateName: String { get }

  /// Ends the field and dismisses the sheet.
  func end()

  /// Ends the card session of `channel`.
  func endChannel(_ channel: Channel)

  /// Sends one harmless command on `channel`; true when the card answered.
  func keepAlive(_ channel: Channel) async -> Bool

  /// Opens the card session and runs PACE with `cardAccessNumber`; nil
  /// when the card did not answer.
  func prepareChannel(cardAccessNumber: String) async -> Channel?

  /// Replaces the line of text on the sheet.
  func show(_ line: NearFieldSheetLine)
}
