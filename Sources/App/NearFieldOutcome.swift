// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// What a warm near field needs to know of an operation's outcome.
internal protocol NearFieldOutcome: Sendable {
  /// Whether the card answered the operation; a field whose card did not
  /// answer is not reused.
  var cardAnswered: Bool { get }

  /// Whether the operation has the card's result.
  var isResult: Bool { get }

  /// The step an operation without the card's result broke at; nil when
  /// it broke at the step running when it ended.
  var failedStep: NearFieldStep? { get }
}
