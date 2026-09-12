// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CardCore
import CryptoTokenKit
import Foundation

/// Removes stored RefineID registrations that should no longer be offered.
internal enum TokenRegistrationRevoker {
  /// Why an automatic registration no longer represents the desired path.
  internal enum Reason {
    /// The card proved that the stored CAN cannot authenticate this field.
    case canRejection

    /// The card rejected the credential authorizing automatic signatures.
    case pin1Rejection

    /// The card rejected the credential authorizing a qualified signature.
    case pin2Rejection

    /// The holder deliberately connected a reader and inserted a usable card.
    case readerMint

    /// Stable diagnostic wording that contains no card or credential data.
    internal var logPrefix: String {
      switch self {
      case .canRejection:
        "CAN rejection"

      case .pin1Rejection:
        "PIN1 rejection"

      case .pin2Rejection:
        "PIN2 rejection"

      case .readerMint:
        "reader mint"
      }
    }
  }

  /// Queues best-effort removal of the exact token registration.
  internal static func revoke(
    _ instanceID: CardInstanceIdentifier,
    reason: Reason
  ) {
    #if os(iOS)
      let tokenID = CardTokenNamespace.tokenIdentifier(for: instanceID)
      DispatchQueue.global(qos: .utility).async {
        let manager = TKSmartCardTokenRegistrationManager.default
        guard manager.registeredSmartCardTokens.contains(tokenID) else {
          TokenLog.info("\(reason.logPrefix) registration already absent")
          return
        }
        do {
          try manager.unregisterSmartCard(tokenID: tokenID)
          TokenLog.notice("\(reason.logPrefix) unregistered token")
        } catch {
          // The persistent PIN and prime are already gone. Even if this
          // index removal fails, the driver cannot mint or sign the token
          // again until the holder deliberately creates a new identity.
          TokenLog.error("\(reason.logPrefix) could not unregister token: \(error)")
        }
      }
    #endif
  }

  /// Removes every persistent RefineID smart-card registration now.
  ///
  /// A connected-reader mint calls this before returning its live token.
  /// The registration manager lists absent-card registrations, not live
  /// reader tokens; filtering with ``CardTokenNamespace/owns`` destroys
  /// every RefineID NFC route without touching Apple, third-party, or the
  /// reader token that was just published.
  ///
  /// Returns how many registrations were removed. The RefineID prime
  /// store is already empty when this runs, so even a registration whose
  /// removal fails cannot mint an NFC token.
  @discardableResult
  internal static func revokeAll(reason: Reason) -> Int {
    #if os(iOS)
      // Without an antenna nothing was registered for the system to summon.
      let manager = TKSmartCardTokenRegistrationManager.default
      let tokenIDs = manager.registeredSmartCardTokens
        .filter(CardTokenNamespace.owns(tokenIdentifier:))
        .sorted()
      guard !tokenIDs.isEmpty else {
        TokenLog.info("\(reason.logPrefix) registrations already absent")
        return 0
      }

      var removed = 0
      var failed = 0
      for tokenID in tokenIDs {
        do {
          try manager.unregisterSmartCard(tokenID: tokenID)
          removed += 1
        } catch {
          failed += 1
        }
      }
      if removed > 0 {
        TokenLog.notice("\(reason.logPrefix) unregistered \(removed) stored identity(s)")
      }
      if failed > 0 {
        TokenLog.error("\(reason.logPrefix) could not unregister \(failed) stored identity(s)")
      }
      return removed
    #else
      return 0
    #endif
  }
}
