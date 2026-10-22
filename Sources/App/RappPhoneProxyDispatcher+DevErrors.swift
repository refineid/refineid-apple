// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if DEBUG && REFINEID_LOCAL_CARD && os(iOS)
  import CardCore
  import Foundation

  /// How the custodian's failed operations reach the development error
  /// display.
  extension RappPhoneProxyDispatcher {
    /// Records that an operation ended without its result.
    ///
    /// The answer and its cause by case only: never the credential, the
    /// attempts left or anything the card returned.
    internal static func reportFailure(_ outcome: RappNfcCardExecutor.Outcome) {
      DevErrorLog.report("operation answered \(Self.devErrorName(outcome))", source: .app)
    }

    /// The answer `finishFailure` gives `outcome`, and why.
    private static func devErrorName(_ outcome: RappNfcCardExecutor.Outcome) -> String {
      switch outcome {
      case .completionAmbiguous:
        "cardError: completion ambiguous"

      case .refusedBeforeCredentialTransmit(let refusal):
        Self.devErrorName(refusal)

      case .rejected(.cardAccessNumber):
        "operationFailed: card access number rejected"

      case .rejected(.credential):
        "retryFloor: PIN refused"

      case .result:
        "nothing: a result on the failure path closed the session"
      }
    }

    /// The answer `finishFailure` gives `refusal`, and why.
    private static func devErrorName(_ refusal: RappCardExecutor.Refusal) -> String {
      switch refusal {
      case .cardUnavailable:
        "cardError: card unavailable"

      case .certificateUnavailable:
        "requestInvalid: certificate unavailable"

      case .credentialBlocked:
        "retryFloor: credential blocked"

      case .credentialInvalidated:
        "retryFloor: credential invalidated"

      case .heldPin1Unconfirmed:
        "operationFailed: held PIN unconfirmed"

      case .invalidCredential:
        "operationFailed: credential invalid"

      case .keyOrAlgorithmMismatch:
        "requestInvalid: key or algorithm mismatch"

      case .retryFloor:
        "retryFloor: attempts reserved for the issuer"
      }
    }
  }
#endif
