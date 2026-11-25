// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

/// Attempts remaining for one credential, as read side-effect-free from the
/// card.
///
/// Raw bytes exist only at parser boundaries;
/// everything downstream works with refined values like this one.
public struct RetryCount: Equatable, Sendable {
  /// Supported cards encode a retry counter in a single low nibble.
  ///
  /// A value above this is a parser or transport fault, never a real
  /// counter, so construction refuses it instead of letting it into the
  /// domain.
  public static let maximumPlausible: UInt8 = 15

  /// The full retry allowance of an untouched credential on FINEID cards: five attempts.
  public static let pristineAllowance: UInt8 = 5

  /// The full retry allowance of an untouched credential on Estonian eID cards: three attempts.
  public static let estonianPristineAllowance: UInt8 = EstonianEidValues.pinRetryLimit

  /// The point at which a credential is one mistake from blocking: the last attempt.
  ///
  /// Operations refuse to spend attempts at or below this, and
  /// presentation names a recovery route instead of a count.
  public static let lowAttemptCeiling: UInt8 = 1

  /// The validated number of attempts remaining.
  public let attemptsRemaining: UInt8

  /// True when this credential retains the FINEID five-attempt allowance.
  public var isPristine: Bool {
    isPristine(allowance: Self.pristineAllowance)
  }

  /// Zero attempts remaining: the credential is blocked.
  public var isBlocked: Bool {
    attemptsRemaining == 0
  }

  /// Refuses any value above `maximumPlausible`.
  public init?(attemptsRemaining: UInt8) {
    guard attemptsRemaining <= Self.maximumPlausible else { return nil }
    self.attemptsRemaining = attemptsRemaining
  }

  /// True when this credential retains its card-specific full allowance.
  public func isPristine(allowance: UInt8) -> Bool {
    attemptsRemaining == allowance
  }
}
