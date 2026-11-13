// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if REFINEID_LOCAL_CARD && os(iOS)

  import CardCore
  import CryptoTokenKit
  import Foundation

  extension CardPriming {
    /// Only transport failures can be recovered by presenting the card again.
    ///
    /// Card refusals, malformed data and storage failures keep their own routes.
    internal static func canRetryRead(after error: any Error) -> Bool {
      switch error {
      case NearFieldCardSession.Failure.antennaBusy,
        NearFieldCardSession.Failure.cardNeverArrived,
        NearFieldCardSession.Failure.readerCoolingDown,
        SmartCardChannel.TransportError.responseTimedOut,
        CardOperationError.sessionUnavailable,
        CardOperationError.exchangeUnanswered,
        Failure.communicationInterrupted,
        Failure.secureChannelTimedOut:
        return true

      default:
        let failure = error as NSError
        return failure.domain == TKErrorDomain
          && (failure.code == TKError.Code.communicationError.rawValue
            || failure.code == TKError.Code.tokenNotFound.rawValue)
      }
    }
  }

#endif
