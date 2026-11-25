// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

/// One counter-safe reading of all three credentials.
public struct CredentialProbeReport: Equatable, Sendable {
  /// PIN1 probe outcome (VERIFY probe form).
  public let pin1: RetryProbeOutcome

  /// PIN2 probe outcome (VERIFY probe form).
  public let pin2: RetryProbeOutcome

  /// PUK probe outcome (GET DATA PIN-container form or VERIFY status probe).
  public let puk: RetryProbeOutcome

  /// Full retry allowance of untouched credentials on the probed card
  /// (five on FINEID, three on Estonian eID).
  public let pristineAllowance: UInt8

  /// Whether PIN 2 still holds its initial value and must be changed before
  /// the signature key can be used (EstEID 2025, GED24035 sections 3.1, 7.8.1,
  /// and 8.3.4).
  public let pin2RequiresChangeBeforeSigning: Bool

  /// The typed retry state, available only when all three probes
  /// returned counters.
  ///
  /// This is diagnostic state. Authentication evaluates the fresh PIN1
  /// outcome alone because PIN2 and PUK are not consumed by that operation.
  public var retryState: CredentialRetryState? {
    guard
      case .remaining(let pin1Count) = pin1,
      case .remaining(let pin2Count) = pin2,
      case .remaining(let pukCount) = puk
    else {
      return nil
    }
    return CredentialRetryState(pin1: pin1Count, pin2: pin2Count, puk: pukCount)
  }

  /// Groups one simultaneous probe of the three credentials under the FINEID
  /// five-try allowance.
  public init(
    pin1: RetryProbeOutcome,
    pin2: RetryProbeOutcome,
    puk: RetryProbeOutcome
  ) {
    self.init(
      pin1: pin1,
      pin2: pin2,
      puk: puk,
      pristineAllowance: RetryCount.pristineAllowance,
      pin2RequiresChangeBeforeSigning: false
    )
  }

  /// Groups one simultaneous probe of the three credentials with the card's
  /// full retry allowance.
  public init(
    pin1: RetryProbeOutcome,
    pin2: RetryProbeOutcome,
    puk: RetryProbeOutcome,
    pristineAllowance: UInt8,
    pin2RequiresChangeBeforeSigning: Bool = false
  ) {
    self.pin1 = pin1
    self.pin2 = pin2
    self.puk = puk
    self.pristineAllowance = pristineAllowance
    self.pin2RequiresChangeBeforeSigning = pin2RequiresChangeBeforeSigning
  }
}
