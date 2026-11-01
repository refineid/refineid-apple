// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CardCore
import SwiftUI

/// User-facing presentation shared by every credential operation.
///
/// Card operations own retry policy and return structured outcomes. This type
/// owns the corresponding wording and typography so management, activation,
/// authentication, and signing do not invent separate rejection messages.
internal enum CredentialOutcomeMessage {
  internal static func rejection(
    _ credential: PresentedCredential,
    remaining: RetryCount
  ) -> String {
    incorrect(credential)
      + "\n"
      + String(
        localized: "You have \(remaining.attemptsRemaining) attempts remaining.")
  }

  /// A retry-floor refusal: the credential that was not presented and
  /// the way back.
  ///
  /// A PIN at one or two attempts, or blocked, is reset with the PUK,
  /// which the floor judges on its own counter. `remaining` is the exact
  /// count when the card supplied it.
  internal static func floorRefusal(
    role: CredentialRole,
    verdict: RetryFloorVerdict,
    remaining: RetryCount?
  ) -> String {
    switch verdict {
    case .refuseBlocked:
      return blocked(role)

    case .refuseLowAttempts:
      guard role != .puk else { return otherSoftwareRecovery() }
      let name = shortName(role)
      let detail =
        switch remaining?.attemptsRemaining {
        case .some(1):
          String(localized: "Only 1 attempt remains for \(name).")

        case .some(let count):
          String(localized: "Only \(count) attempts remain for \(name).")

        case .none:
          String(localized: "RefineID does not use either of the last two attempts.")
        }
      return String(localized: "Operation refused.")
        + "\n"
        + detail
        + "\n"
        + resetWithPuk(role)

    case .refuseUnreadable, .proceed:
      return String(localized: "The operation was not sent.")
    }
  }

  /// A blocked credential and the way back: the PUK for a PIN, the
  /// issuer for the PUK.
  internal static func blocked(_ role: CredentialRole) -> String {
    switch role {
    case .pin1:
      String(localized: "PIN 1 is blocked.") + "\n" + resetWithPuk(role)

    case .pin2:
      String(localized: "PIN 2 is blocked.") + "\n" + resetWithPuk(role)

    case .puk:
      unrecoverableCard()
    }
  }

  internal static func recoveryGuidance(for role: CredentialRole) -> String {
    switch role {
    case .pin1:
      String(localized: "RefineID does not use PIN 1 with fewer than 3 attempts left.")
        + "\n"
        + String(localized: "Reset PIN 1 with the PUK, or use other software.")

    case .pin2:
      String(localized: "RefineID does not use PIN 2 with fewer than 3 attempts left.")
        + "\n"
        + String(localized: "Reset PIN 2 with the PUK, or use other software.")

    case .puk:
      preconditionFailure("PUK is the recovery credential, not a reset target")
    }
  }

  private static func resetWithPuk(_ role: CredentialRole) -> String {
    switch role {
    case .pin1:
      String(localized: "Reset PIN 1 with your PUK.")

    case .pin2:
      String(localized: "Reset PIN 2 with your PUK.")

    case .puk:
      preconditionFailure("PUK is the recovery credential, not a reset target")
    }
  }

  private static func shortName(_ role: CredentialRole) -> String {
    switch role {
    case .pin1:
      "PIN 1"

    case .pin2:
      "PIN 2"

    case .puk:
      "PUK"
    }
  }

  internal static func otherSoftwareRecovery() -> String {
    String(localized: "Use other software to recover the card.")
      + "\n"
      + String(
        localized: "RefineID will not use either of the final two PUK attempts.")
  }

  internal static func unrecoverableCard() -> String {
    String(localized: "The PUK is blocked.")
      + "\n"
      + String(localized: "This card cannot be recovered with software.")
  }

  internal static func incorrect(_ credential: PresentedCredential) -> String {
    switch credential {
    case .pin1:
      String(localized: "PIN 1 is incorrect.")

    case .pin2:
      String(localized: "PIN 2 is incorrect.")

    case .puk:
      String(localized: "PUK is incorrect.")

    case .activationCode, .activationPin:
      String(localized: "Activation PIN is incorrect.")
    }
  }
}
