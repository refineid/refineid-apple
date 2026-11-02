// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// Opens an organization card on an antenna with the PIN an operation
/// spends.
///
/// PACE runs with PIN 1 or PIN 2 as its password (FINEID S1 v4.0,
/// organizational cards, section 2.1). The retry floor decides on the
/// state MSE:Set AT reports, before the first GENERAL AUTHENTICATE, where
/// the card takes a try that it returns only when the handshake completes.
/// A completed PACE counts as that PIN verified, so nothing here sends a
/// VERIFY, and the card refuses a VERIFY status probe inside the channel.
///
/// Every failure is the ``PaceEstablishment/Failure`` the handshake
/// threw, or the card's refusal of the application select after it.
public enum OrganizationCardOpening {
  /// What an opened channel carries.
  public struct Opened {
    /// The operations over the secure channel, marked with the PIN that
    /// opened it.
    public let operations: CardOperations

    /// The PIN's state as MSE:Set AT reported it.
    public let pinState: RetryProbeOutcome
  }

  /// PACE with PIN 1, then the FINEID application selected in the channel,
  /// where the authentication key signs.
  public static func pin1(
    over channel: any CardChannel,
    _ pin: consuming Pin1Transmission,
    spending: PinAdmission.Spending
  ) throws -> Opened {
    let opened = try Self.opened(
      over: channel,
      password: PacePassword(pin1: pin, spending: spending),
      role: .pin1)
    try opened.operations.selectFineidApplication()
    return opened
  }

  /// PACE with PIN 2; the card stays at the main file, from which the
  /// operation selects DF.ESIGN (FINEID S4-2 v4.0 section 4.6.21).
  public static func pin2(
    over channel: any CardChannel,
    _ pin: consuming Pin2Transmission
  ) throws -> Opened {
    try Self.opened(over: channel, password: PacePassword(pin2: pin), role: .pin2)
  }

  private static func opened(
    over channel: any CardChannel,
    password: consuming PacePassword,
    role: CredentialRole
  ) throws -> Opened {
    let established = try PaceEstablishment(channel: channel).establish(with: password)
    guard let pinState = established.pinState else {
      throw PaceEstablishment.Failure.malformedResponse
    }
    let secure = SecureMessagingChannel(wrapping: channel, sessionKeys: established.keys)
    return Opened(
      operations: CardOperations(channel: secure, openedWith: role),
      pinState: pinState)
  }
}
