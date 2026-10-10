// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CardCore
import Foundation

/// One localized failure vocabulary shared by macOS and iOS signing.
internal enum DocumentSigningMessage {
  /// The title over any signing failure.
  internal static var title: String {
    text("error.title", "Signing failed")
  }

  internal static func message(for error: Error) -> String {
    if let signerFailure = error as? DocumentSigner.Failure {
      return documentSignerMessage(signerFailure)
    }
    if let asicFailure = error as? AsicSigner.Failure {
      return asicSignerMessage(asicFailure)
    }
    if let clientError = error as? RappRequesterClientError {
      return remoteClientMessage(clientError)
    }
    return text("error.generic", "The documents could not be signed.")
  }

  private static func documentSignerMessage(_ failure: DocumentSigner.Failure) -> String {
    switch failure {
    case .card(let outcome):
      cardMessage(outcome)

    case .document(let detail):
      documentMessage(detail)

    case .remote(let detail):
      remoteAnswerMessage(detail)

    case .network:
      text(
        "error.network",
        "A timestamp or revocation service could not be reached. Nothing was written.")

    case .validation(let evidence):
      validationMessage(evidence)

    case .stampSignerChanged:
      text("error.cardChanged", "The signing card changed. Nothing was written.")
    }
  }

  private static func asicSignerMessage(_ failure: AsicSigner.Failure) -> String {
    switch failure {
    case .container:
      text("error.container", "The signed container could not be written.")

    case .signedOctetsChanged:
      text(
        "error.unexpectedSignature",
        "The card signed unexpected data. Nothing was written.")

    case .unusableName:
      text(
        "error.names",
        "Two documents have the same name, or a name is reserved. Rename one and try again.")
    }
  }

  private static func remoteClientMessage(_ error: RappRequesterClientError) -> String {
    switch error {
    case .noActivePair, .noSelectedPair:
      text("error.remoteNotPaired", "No phone is paired.")

    case .peerNotFound, .timedOut:
      text("error.remoteTimeout", "The paired phone did not respond.")

    case .transport:
      text("error.remoteDisconnected", "The connection to the paired phone was lost.")

    case .terminal(let reason):
      terminalReasonMessage(reason)

    case .protocolFailure, .unexpectedResult:
      remoteAnswerMessage(.noSignature)
    }
  }

  private static func remoteAnswerMessage(_ failure: DocumentSigner.RemoteFailure) -> String {
    switch failure {
    case .noSignature:
      text("error.remoteNoSignature", "The phone did not return a signature. Nothing was written.")

    case .unverifiedSignature:
      text(
        "error.remoteUnverified",
        "The signature from the phone did not match the card's certificate. Nothing was written.")

    case .unusableCertificate:
      text(
        "error.remoteCertificate",
        "The certificate on the phone's card cannot be used for signing.")
    }
  }

  private static func terminalReasonMessage(
    _ reason: RappOperationDriver.TerminalReason?
  ) -> String {
    switch reason {
    case .userDenied:
      text(
        "error.remoteDenied",
        "The signature request was declined on the paired phone.")

    case .invalidCredential:
      CredentialOutcomeMessage.incorrect(credentialName: "PIN 2")

    case .credentialRejected:
      pin2BlockedMessage()

    case .retryPolicyRefused:
      CredentialOutcomeMessage.lowAttemptRefusal()

    case .requestExpired:
      text("error.remoteExpired", "The request was not approved on the phone in time.")

    case .cancelled:
      text("error.remoteCancelled", "The signature request was cancelled.")

    case .requestInvalidOrUnsupported:
      text("error.remoteUnsupported", "The phone cannot make this kind of signature.")

    case .cardRemovedBeforeTransmit:
      text("error.remoteCardRemoved", "The card was removed before signing.")

    case .cardCompletionAmbiguous:
      text("error.remoteAmbiguous", "The card's answer was lost. Nothing was written.")

    case nil:
      remoteAnswerMessage(.noSignature)
    }
  }

  private static func cardMessage(_ outcome: CardMaintenance.Outcome) -> String {
    switch outcome {
    case .rejected(let remaining):
      CredentialOutcomeMessage.rejection(
        credentialName: "PIN 2", remaining: remaining)

    case .pinBlocked, .floorRefused(.refuseBlocked):
      pin2BlockedMessage()

    case .floorRefused(.refuseLowAttempts):
      CredentialOutcomeMessage.lowAttemptRefusal()

    case .invalidated:
      text(
        "error.notActivated",
        "The signature PIN is not activated. Activate the card first.")

    case .noCard:
      text("error.noCard", "No readable identity card was found.")

    default:
      text("error.cardFailed", "The card did not complete the signature.")
    }
  }

  private static func pin2BlockedMessage() -> String {
    text("error.pin2Blocked", "PIN 2 is blocked. Reset it in PIN settings.")
  }

  private static func documentMessage(_ failure: PdfSigningError) -> String {
    switch failure {
    case .notAPdf:
      text("error.notPDF", "The selected file is not a PDF.")

    case .encrypted:
      text("error.encryptedPDF", "That PDF is encrypted and cannot be modified.")

    case .crossReferenceStreamUnsupported:
      text(
        "error.pdfEncoding",
        "That PDF uses an unsupported cross-reference encoding.")

    case .signatureTooLarge:
      text("error.signatureTooLarge", "The signature did not fit in the PDF.")

    default:
      text("error.pdfStructure", "That PDF structure could not be read.")
    }
  }

  private static func validationMessage(_ failure: Error) -> String {
    switch failure {
    case ValidationMaterialCollector.Failure.revoked(.documentSigner):
      text("error.cardRevoked", "The card is revoked and cannot sign.")

    case ValidationMaterialCollector.Failure.revoked(.timestampAuthority):
      text(
        "error.timestampRevoked",
        "The timestamp service certificate is revoked.")

    default:
      text(
        "error.validation",
        "Authenticated certificate and revocation evidence could not be collected.")
    }
  }

  private static func text(
    _ key: StaticString,
    _ fallback: String.LocalizationValue
  ) -> String {
    String(localized: key, defaultValue: fallback, table: "DocumentSigning")
  }
}
