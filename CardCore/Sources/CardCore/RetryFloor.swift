// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

/// Every CTK PIN-bearing command obtains fresh retry state first,
/// side-effect-free, and this rule decides whether the operation may proceed.
///
/// A credential is presented only with at least
/// `minimumAttemptsToProceed` attempts left, or when it is already
/// verified. One or two attempts left and an unreadable counter are
/// refused: RefineID never spends an attempt that could block the card.
/// A blocked PIN is refused too. A blocked PUK, or one at no tries left,
/// goes to the card (`evaluate(probeOutcome:presenting:)`), and so does
/// a preset activation PIN (`evaluateLastTries(probeOutcome:)`): the card
/// answers for itself and spends nothing, and the software cannot know
/// whether the code in the holder's hand is a PUK or an activation PIN,
/// so it must not close a recovery the card would allow. Each operation
/// judges the credential it presents, so a reset presents the PUK and is
/// judged on the PUK's counter whatever the PIN it resets shows.
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

  /// Decides for the credential `role` presents in ordinary use.
  ///
  /// PIN 1 and PIN 2 take the floor as it stands. The PUK takes the
  /// last-tries rule: refused at one or two tries left and at an
  /// unreadable counter, but at no tries left or blocked the operation
  /// proceeds to the card, which refuses by itself without spending
  /// anything.
  public static func evaluate(
    probeOutcome: RetryProbeOutcome,
    presenting role: CredentialRole
  ) -> RetryFloorVerdict {
    switch role {
    case .pin1, .pin2:
      evaluate(probeOutcome: probeOutcome)

    case .puk:
      evaluateLastTries(probeOutcome: probeOutcome)
    }
  }

  /// Refuses only where a last try would be spent or the counter cannot
  /// be read: one or two tries left, or no reading.
  ///
  /// At no tries left or blocked the operation proceeds: the card
  /// answers for itself and spends nothing. This is the rule for every
  /// credential an activation presents - the PUK under the
  /// activation-code scheme and each preset PIN under the
  /// activation-PIN scheme - since which code the holder has in hand is
  /// inferred from the card, never known, and the software must not
  /// close a recovery the card would allow.
  public static func evaluateLastTries(probeOutcome: RetryProbeOutcome) -> RetryFloorVerdict {
    let verdict = evaluate(probeOutcome: probeOutcome)
    return verdict == .refuseBlocked ? .proceed : verdict
  }
}
