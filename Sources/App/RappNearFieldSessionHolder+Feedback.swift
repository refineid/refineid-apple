// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if REFINEID_LOCAL_CARD && os(iOS)
  import Foundation

  /// What the holder tells the person at the sheet after an operation.
  extension RappNearFieldSessionHolder {

    internal func reportFeedback(
      for result: RappCardExecutor.Outcome?,
      session: NearFieldCardSession
    ) async {
      if case .result = result {
        session.update(message: String(localized: "Card read successfully."))
        await MainActor.run {
          CardPrimingFeedback.report(succeeded: true)
        }
      } else {
        // No outcome means the channel was never prepared or the command
        // never reached the card; the holder sees the same failure.
        session.update(
          message: String(localized: "The card could not be read. Hold it still and try again.")
        )
        await MainActor.run {
          CardPrimingFeedback.report(succeeded: false)
        }
      }
    }
  }
#endif
