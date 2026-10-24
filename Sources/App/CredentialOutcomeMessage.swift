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
    credentialName: String,
    remaining: RetryCount
  ) -> String {
    incorrect(credentialName: credentialName)
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
      return String(localized: "Operation refused")
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
      String(localized: "PIN 1 is blocked") + "." + "\n" + resetWithPuk(role)

    case .pin2:
      String(localized: "PIN 2 is blocked") + "." + "\n" + resetWithPuk(role)

    case .puk:
      unrecoverableCard()
    }
  }

  /// Which credentials have spent attempts, and the way back to the
  /// full allowance: one correct entry.
  internal static func spentAttemptsNotice(
    _ spent: [(name: String, remaining: RetryCount)]
  ) -> String {
    let full = Int(RetryCount.pristineAllowance)
    let lines = spent.map { entry in
      String(
        localized:
          "\(entry.name): \(Int(entry.remaining.attemptsRemaining)) of \(full) attempts left."
      )
    }
    return lines.joined(separator: "\n")
      + "\n"
      + String(localized: "A correct entry restores the full count.")
  }

  internal static func recoveryGuidance(for role: CredentialRole) -> String {
    switch role {
    case .pin1:
      String(localized: "PIN 1 requires recovery") + "\n" + resetWithPuk(role)

    case .pin2:
      String(localized: "PIN 2 requires recovery") + "\n" + resetWithPuk(role)

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
    String(localized: "Use other software to recover the card")
      + "\n"
      + String(
        localized: "RefineID will not use either of the final two PUK attempts.")
  }

  internal static func unrecoverableCard() -> String {
    String(localized: "The PUK is blocked")
      + "\n"
      + String(localized: "This card cannot be recovered with software.")
  }

  internal static func incorrect(credentialName: String) -> String {
    switch credentialName {
    case "PIN 1":
      String(localized: "PIN 1 is incorrect.")

    case "PIN 2":
      String(localized: "PIN 2 is incorrect.")

    case "PUK":
      String(localized: "PUK is incorrect.")

    case "activation code":
      String(localized: "Activation code is incorrect.")

    case "activation PIN":
      String(localized: "Activation PIN is incorrect.")

    default:
      "\(credentialName) is incorrect."
    }
  }
}
