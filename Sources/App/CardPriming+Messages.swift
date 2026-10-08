// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if REFINEID_LOCAL_CARD && os(iOS)

  import CardCore
  import Foundation

  /// How a failed hold is explained, on the sheet and afterwards.
  extension CardPriming {
    /// What the NFC sheet says when a hold fails.
    ///
    /// The sheet is the only surface a holder can see while a card is
    /// against the phone, so it carries the reason rather than a shrug.
    /// It never carries an internal error description: Apple's panel has
    /// room for one short line, while the app retains the fuller sanitized
    /// result after the panel closes.
    internal static func sheetMessage(for error: any Error) -> String {
      if case Failure.pin1LowAttempts = error {
        return String(localized: "Operation refused")
      }
      if case Failure.secureChannelTimedOut = error {
        return String(localized: "Connection timed out")
      }
      if let failure = error as? CardOperationError {
        switch failure {
        case .pinRejected:
          return CredentialOutcomeMessage.incorrect(credentialName: "PIN 1")

        case .pinBlocked:
          return String(localized: "PIN 1 is blocked")

        default:
          break
        }
      }
      return Self.summary(for: error)
    }

    internal static func summary(for error: any Error) -> String {
      if let failure = error as? Failure {
        return Self.summary(for: failure)
      }
      if let failure = error as? NearFieldCardSession.Failure {
        return Self.summary(for: failure)
      }
      if let failure = error as? CardOperationError {
        return Self.summary(for: failure)
      }
      return String(localized: "The card could not be read. Hold it still and try again.")
    }

    /// Explains a card refusal without exposing its status word or raw error.
    private static func summary(for failure: CardOperationError) -> String {
      switch failure {
      case .pinRejected(let remaining):
        return CredentialOutcomeMessage.rejection(
          credentialName: "PIN 1",
          remaining: remaining)

      case .pinBlocked:
        return String(localized: "PIN 1 is blocked") + "."

      default:
        return String(localized: "The card could not be read. Hold it still and try again.")
      }
    }

    /// Explains an app-level priming failure.
    private static func summary(for failure: Failure) -> String {
      switch failure {
      case Failure.activationRequired:
        String(localized: "Activate this card first, then try setup again.")

      case Failure.cardAccessNumberMissing:
        String(localized: "Store the card access number first, then try again.")

      case Failure.secureChannelTimedOut:
        String(localized: "The card security delay timed out. Hold the card still and try again.")

      case Failure.wrongCardAccessNumber:
        String(localized: "The Card Access Number (CAN) is incorrect.")

      case Failure.pin1Malformed:
        String(localized: "PIN 1 does not fit its digit rules.")

      case Failure.pin1Unavailable:
        String(localized: "PIN 1 could not be verified safely.")

      case Failure.pin1LowAttempts(let remaining):
        CredentialOutcomeMessage.lowAttemptRefusal(
          credentialName: "PIN 1",
          remaining: remaining)

      case Failure.certificateUnreadable:
        String(localized: "The card did not return a usable certificate.")

      case Failure.primeNotStored:
        String(localized: "The card details could not be stored on this iPhone.")

      case Failure.unidentifiedCard:
        String(localized: "The card was not recognized. Try holding it again.")
      }
    }

    /// Explains a CryptoTokenKit registration-field failure.
    private static func summary(for failure: NearFieldCardSession.Failure) -> String {
      switch failure {
      case .antennaBusy:
        String(localized: "The phone's card reader is busy. Try again in a moment.")

      case .cardNeverArrived:
        String(localized: "No card was found. Hold the card against the top of the phone.")

      case .readerCoolingDown:
        String(localized: "The phone's card reader is cooling down. Try again in a minute.")

      case .slotRefused:
        String(localized: "This iPhone would not open a card reading session.")

      case .dismissed:
        String(localized: "Setup was cancelled.")
      }
    }
  }

#endif
