// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

/// Every CTK PIN-bearing command obtains fresh retry state first,
/// side-effect-free, and this rule decides whether the operation may proceed.
///
/// A credential is presented only with at least
/// `minimumAttemptsToProceed` attempts left, or when it is already
/// verified. One or two attempts left, a blocked credential and an
/// unreadable counter are refused: RefineID never spends an attempt that
/// could block the card. Each operation judges the credential it presents,
/// so a reset presents the PUK and is judged on the PUK's counter whatever
/// the PIN it resets shows.
public enum RetryFloor {
  private enum Constants {
    static let minimumAttemptsToProceed: UInt8 = 3
  }

  /// An operation proceeds only when at least this many attempts remain.
  public static let minimumAttemptsToProceed: UInt8 = Constants.minimumAttemptsToProceed

  /// Decides from one fresh reading.
  ///
  /// Pass nil when the state could not be read or did not parse - the
  /// verdict then fails closed.
  ///
  /// Freshness is the caller's obligation: the reading must come from the
  /// same exclusive card transaction that will carry the PIN command,
  /// immediately before it.
  public static func evaluate(freshReading: RetryCount?) -> RetryFloorVerdict {
    guard let reading = freshReading else { return .refuseUnreadable }
    if reading.isBlocked {
      return .refuseBlocked
    }
    if reading.attemptsRemaining < Constants.minimumAttemptsToProceed {
      return .refuseLowAttempts
    }
    return .proceed
  }

  /// Decides from one credential's side-effect-free probe outcome.
  ///
  /// A terminal lock is distinct from an unreadable response so the
  /// caller can diagnose it without consulting unrelated credentials.
  ///
  /// A verified answer proceeds: a successful VERIFY resets the
  /// credential's retry counter to its maximum (S1 v4.2 §3.5), so the
  /// probe's `9000` proves a full counter even though it carries no
  /// count. The state is routine on the organization card, whose
  /// credentials are global security data objects (S4-2 v4.0 §4.2):
  /// their verified flag survives re-selecting the application, so
  /// every signature after the first in one session probes as
  /// verified.
  public static func evaluate(probeOutcome: RetryProbeOutcome) -> RetryFloorVerdict {
    switch probeOutcome {
    case .remaining(let reading):
      return evaluate(freshReading: reading)

    case .verified:
      return .proceed

    case .locked:
      return .refuseBlocked

    case .invalidated, .noInformation, .other:
      return .refuseUnreadable
    }
  }
}
