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
    rejection(credential, remaining: remaining, numbering: nil)
  }

  internal static func rejection(
    _ credential: PresentedCredential,
    remaining: RetryCount,
    numbering: CredentialReferenceSet?
  ) -> String {
    let remainingSentence =
      if remaining.attemptsRemaining == 1 {
        String(localized: "You have 1 attempt remaining.")
      } else {
        String(localized: "You have \(remaining.attemptsRemaining) attempts remaining.")
      }
    return incorrect(credential, numbering: numbering) + "\n" + remainingSentence
  }

  /// A retry-floor refusal: the credential that was not presented and
  /// the way back.
  ///
  /// A PIN on its last attempt is reset with the PUK, which the floor
  /// judges on its own counter. `remaining` is the exact count when the
  /// card supplied it. A blocked PIN is not a refusal: its command went to
  /// the card, and ``blocked(_:numbering:)`` words the answer.
  internal static func floorRefusal(
    role: CredentialRole,
    verdict: RetryFloorVerdict,
    remaining: RetryCount?
  ) -> String {
    floorRefusal(role: role, verdict: verdict, remaining: remaining, numbering: nil)
  }

  internal static func floorRefusal(
    role: CredentialRole,
    verdict: RetryFloorVerdict,
    remaining: RetryCount?,
    numbering: CredentialReferenceSet?
  ) -> String {
    switch verdict {
    case .refuseLowAttempts:
      guard role != .puk else { return otherSoftwareRecovery() }
      let detail = lowAttemptDetail(
        role: role,
        remaining: remaining?.attemptsRemaining,
        estonian: isEstonian(numbering)
      )
      return String(localized: "Operation refused.")
        + "\n"
        + detail
        + "\n"
        + resetWithPuk(role, numbering: numbering)

    case .refuseUnreadable, .proceed:
      return String(localized: "The operation was not sent.")
    }
  }

  /// A blocked credential and the way back: the PUK for a PIN, the
  /// issuer for a PUK the card itself has answered blocked.
  internal static func blocked(_ role: CredentialRole) -> String {
    blocked(role, numbering: nil)
  }

  internal static func blocked(
    _ role: CredentialRole,
    numbering: CredentialReferenceSet?
  ) -> String {
    let estonian = isEstonian(numbering)
    switch (role, estonian) {
    case (.pin1, true):
      return String(localized: "PIN 1 is blocked.")
        + "\n"
        + resetWithPuk(role, numbering: numbering)

    case (.pin2, true):
      return String(localized: "PIN 2 is blocked.")
        + "\n"
        + resetWithPuk(role, numbering: numbering)

    case (.pin1, false):
      return String(localized: "Basic PIN 1 is blocked.")
        + "\n"
        + resetWithPuk(role, numbering: numbering)

    case (.pin2, false):
      return String(localized: "Signature PIN 2 is blocked.")
        + "\n"
        + resetWithPuk(role, numbering: numbering)

    case (.puk, _):
      return pukBlockedByCard()
    }
  }

  internal static func recoveryGuidance(for role: CredentialRole) -> String {
    recoveryGuidance(for: role, numbering: nil)
  }

  internal static func recoveryGuidance(
    for role: CredentialRole,
    numbering: CredentialReferenceSet?
  ) -> String {
    let estonian = isEstonian(numbering)
    switch (role, estonian) {
    case (.pin1, true):
      return String(localized: "RefineID does not use PIN 1 on the last attempt.")
        + "\n"
        + String(localized: "Reset PIN 1 with the PUK, or use other software.")

    case (.pin2, true):
      return String(localized: "RefineID does not use PIN 2 on the last attempt.")
        + "\n"
        + String(localized: "Reset PIN 2 with the PUK, or use other software.")

    case (.pin1, false):
      return String(localized: "RefineID does not use Basic PIN 1 on the last attempt.")
        + "\n"
        + String(localized: "Reset Basic PIN 1 with the PUK, or use other software.")

    case (.pin2, false):
      return String(localized: "RefineID does not use Signature PIN 2 on the last attempt.")
        + "\n"
        + String(localized: "Reset Signature PIN 2 with the PUK, or use other software.")

    case (.puk, _):
      preconditionFailure("PUK is the recovery credential, not a reset target")
    }
  }

  internal static func otherSoftwareRecovery() -> String {
    String(localized: "Use other software to recover the card.")
      + "\n"
      + String(localized: "RefineID does not use the last PUK attempt.")
  }

  /// The card's own answer to a PUK: nothing was spent, and no software
  /// command resets a PUK.
  internal static func pukBlockedByCard() -> String {
    String(localized: "The card answered that the PUK is blocked.")
      + "\n"
      + String(localized: "Software cannot reset a PUK; contact the card issuer.")
  }

  internal static func incorrect(_ credential: PresentedCredential) -> String {
    incorrect(credential, numbering: nil)
  }

  internal static func incorrect(
    _ credential: PresentedCredential,
    numbering: CredentialReferenceSet?
  ) -> String {
    let estonian = isEstonian(numbering)
    switch (credential, estonian) {
    case (.pin1, true):
      return String(localized: "PIN 1 is incorrect.")

    case (.pin2, true):
      return String(localized: "PIN 2 is incorrect.")

    case (.pin1, false):
      return String(localized: "Basic PIN 1 is incorrect.")

    case (.pin2, false):
      return String(localized: "Signature PIN 2 is incorrect.")

    case (.puk, _):
      return String(localized: "PUK is incorrect.")

    case (.activationCode, _), (.activationPin, _):
      return String(localized: "Activation PIN is incorrect.")
    }
  }

  private static func lowAttemptDetail(
    role: CredentialRole,
    remaining: UInt8?,
    estonian: Bool
  ) -> String {
    guard let count = remaining else {
      return String(localized: "RefineID does not use the last attempt.")
    }
    return estonian
      ? estonianLowAttemptDetail(role: role, count: count)
      : defaultLowAttemptDetail(role: role, count: count)
  }

  private static func estonianLowAttemptDetail(role: CredentialRole, count: UInt8) -> String {
    switch (role, count) {
    case (.pin1, 1):
      String(localized: "Only 1 attempt remains for PIN 1.")

    case (.pin2, 1):
      String(localized: "Only 1 attempt remains for PIN 2.")

    case (.pin1, _):
      String(localized: "Only \(count) attempts remain for PIN 1.")

    case (.pin2, _):
      String(localized: "Only \(count) attempts remain for PIN 2.")

    case (.puk, _):
      preconditionFailure("PUK is the recovery credential, not a reset target")
    }
  }

  private static func defaultLowAttemptDetail(role: CredentialRole, count: UInt8) -> String {
    switch (role, count) {
    case (.pin1, 1):
      String(localized: "Only 1 attempt remains for Basic PIN 1.")

    case (.pin2, 1):
      String(localized: "Only 1 attempt remains for Signature PIN 2.")

    case (.pin1, _):
      String(localized: "Only \(count) attempts remain for Basic PIN 1.")

    case (.pin2, _):
      String(localized: "Only \(count) attempts remain for Signature PIN 2.")

    case (.puk, _):
      preconditionFailure("PUK is the recovery credential, not a reset target")
    }
  }

  private static func resetWithPuk(
    _ role: CredentialRole,
    numbering: CredentialReferenceSet?
  ) -> String {
    let estonian = isEstonian(numbering)
    switch (role, estonian) {
    case (.pin1, true):
      return String(localized: "Reset PIN 1 with your PUK.")

    case (.pin2, true):
      return String(localized: "Reset PIN 2 with your PUK.")

    case (.pin1, false):
      return String(localized: "Reset Basic PIN 1 with your PUK.")

    case (.pin2, false):
      return String(localized: "Reset Signature PIN 2 with your PUK.")

    case (.puk, _):
      preconditionFailure("PUK is the recovery credential, not a reset target")
    }
  }

  private static func isEstonian(_ numbering: CredentialReferenceSet?) -> Bool {
    numbering == .estonian2018 || numbering == .estonian2025
  }
}
