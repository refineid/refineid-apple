// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

/// The side-effect-free check before activation (FINEID S4-1 §4.6).
public enum ActivationPreflight {
  /// Evaluates one PIN's readiness from counter-safe probes alone.
  ///
  /// Judged per PIN, because §4.6 sets each PIN's changed flag
  /// individually and an interrupted activation leaves one PIN set
  /// and the other in its factory state. A card is awaiting
  /// activation while any of its PINs is; the set one is skipped, not
  /// set again.
  ///
  /// The changed flag is the authority under both schemes: activation
  /// sets it, so `unchanged` is the factory state and `changed` means
  /// the holder has set the PIN. Under the activation-code scheme
  /// (§4.6.1) the factory PINs are blocked, which the card reports as
  /// a blocked or invalidated method or as an exhausted counter; a
  /// blocked PIN whose flag reads `changed` was activated and then
  /// used up, and belongs to PUK recovery.
  ///
  /// When the flag cannot be read, §4.6.1 falls back to the counter:
  /// a blocked, invalidated or exhausted PIN is served the activation,
  /// which is the same RESET RETRY COUNTER under the PUK that recovery
  /// sends. Under the preset-PIN scheme (§4.6.2) a healthy counter is
  /// the expected fresh state and proves nothing, so only `changed`
  /// blocks the flow there.
  public static func evaluate(
    scheme: ActivationScheme,
    probe: RetryProbeOutcome?,
    changeRecord: PinChangeRecord
  ) -> ActivationReadiness {
    switch changeRecord {
    case .changed:
      return .alreadyActivated

    case .unchanged:
      return .ready

    case .unreadable:
      break
    }
    switch scheme {
    case .presetActivationPin:
      return .ready

    case .activationCodeIsPuk:
      switch probe {
      case .locked, .invalidated:
        return .ready

      case .remaining(let count):
        return count.isBlocked ? .ready : .alreadyActivated

      case .verified, .noInformation, .other, .none:
        return .alreadyActivated
      }
    }
  }
}
