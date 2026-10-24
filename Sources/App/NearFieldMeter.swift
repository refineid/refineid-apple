// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// The progress meter drawn inside the system NFC sheet: the operation's
/// name on the first line, one ball per step on the second.
///
/// The sheet is where the holder is looking -- the card is against the
/// phone and the app is behind Apple's own panel -- and the panel takes
/// no views: its message is the entire drawing surface, one string. A
/// failure's sentence replaces the message (``NearFieldSheet``).
///
/// The markers are literal glyphs rather than escapes, by a deliberate
/// exception to this repository's ASCII-only source rule: the sheet is a
/// drawing surface made of text, and a table of escapes hides what it
/// actually draws. Each one still names its codepoint.
internal struct NearFieldMeter: Equatable, Sendable {
  /// U+1F535 LARGE BLUE CIRCLE: a step this hold has reached.
  internal static let reached = "🔵"

  /// U+26AA MEDIUM WHITE CIRCLE: a step not yet reached.
  internal static let waiting = "⚪"

  /// U+1F534 LARGE RED CIRCLE: a step that broke.
  internal static let failed = "🔴"

  /// Space between markers, so the balls read as a row rather than one
  /// blob.
  internal static let markerGap = " "

  /// Space between the row and the seconds of a security delay.
  internal static let textGap = "  "

  /// Between the operation's name and the row.
  internal static let lineBreak = "\n"

  /// What the sheet says when an operation for a paired computer ended
  /// without the card's result.
  internal static var cardNotRead: String {
    String(localized: "The card could not be read. Hold it still and try again.")
  }

  /// The operation drawn.
  internal let operation: NearFieldOperation

  /// One state per step of ``operation``, in step order.
  internal private(set) var states: [NearFieldStep.State]

  /// The balls alone, one per step.
  internal var markers: String {
    states.map(Self.marker).joined(separator: Self.markerGap)
  }

  /// The whole message: the operation's name, then the balls.
  internal var text: String {
    operation.title + Self.lineBreak + markers
  }

  /// The first step not yet done; nil when every step is.
  private var firstUnfinished: Int? {
    states.firstIndex { $0 != .done }
  }

  /// Whether a step broke.
  private var hasBroken: Bool {
    states.contains(.failed)
  }

  /// A meter with no step reached.
  internal init(_ operation: NearFieldOperation) {
    self.operation = operation
    states = Array(repeating: .waiting, count: operation.steps.count)
  }

  /// The marker a step's state is drawn as.
  ///
  /// A step being worked on right now counts as reached: the holder is
  /// watching a row fill up, and splitting "started" from "finished"
  /// would add a third colour to answer a question nobody holding a card
  /// is asking.
  private static func marker(_ state: NearFieldStep.State) -> String {
    switch state {
    case .done, .running:
      Self.reached

    case .failed:
      Self.failed

    case .waiting:
      Self.waiting
    }
  }

  /// The message during a card's security delay: the operation's name,
  /// then the balls and the seconds left, or the whole message once none
  /// are.
  internal func recoveryText(remainingSeconds: Int) -> String {
    guard remainingSeconds > 0 else { return text }
    return text + Self.textGap + "\(remainingSeconds)s"
  }

  /// `step` runs now and every step before it is done.
  ///
  /// A step the operation does not have, one behind the progress already
  /// drawn, or any step once one broke, changes nothing.
  internal mutating func reach(_ step: NearFieldStep) {
    guard let index = operation.steps.firstIndex(of: step), !hasBroken else { return }
    guard index >= firstUnfinished ?? states.count else { return }
    for earlier in states.indices where earlier < index {
      states[earlier] = .done
    }
    states[index] = .running
  }

  /// The step running now is done and the next one runs.
  internal mutating func advance() {
    guard let current = firstUnfinished, !hasBroken else { return }
    states[current] = .done
    let next = current + 1
    if next < states.count {
      states[next] = .running
    }
  }

  /// Every step is done.
  internal mutating func finish() {
    guard !hasBroken else { return }
    states = Array(repeating: .done, count: states.count)
  }

  /// The operation broke at `step`: every step before it is done and
  /// every step after it waits.
  ///
  /// With no step, or one the operation does not have, the first step
  /// not yet done is the one that broke. A meter already finished or
  /// broken stays as it is.
  internal mutating func fail(at step: NearFieldStep?) {
    guard !hasBroken, let unfinished = firstUnfinished else { return }
    let broken = step.flatMap { operation.steps.firstIndex(of: $0) } ?? unfinished
    for index in states.indices {
      states[index] =
        index < broken ? .done : index == broken ? .failed : .waiting
    }
  }
}
