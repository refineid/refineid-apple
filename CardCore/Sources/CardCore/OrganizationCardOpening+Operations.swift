// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

extension OrganizationCardOpening {
  /// PACE with PIN 1 over the plain channel `plain` speaks on.
  public static func pin1(
    over plain: CardOperations,
    _ pin: consuming Pin1Transmission,
    spending: PinAdmission.Spending,
    onPinState: ((RetryProbeOutcome) -> Void)? = nil
  ) throws -> Opened {
    try Self.pin1(over: plain.channel, pin, spending: spending, onPinState: onPinState)
  }

  /// PACE with PIN 2 over the plain channel `plain` speaks on.
  public static func pin2(
    over plain: CardOperations,
    _ pin: consuming Pin2Transmission
  ) throws -> Opened {
    try Self.pin2(over: plain.channel, pin)
  }
}
