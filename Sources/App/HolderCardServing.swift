// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(iOS) && REFINEID_LOCAL_CARD

  import CardCore
  import CryptoTokenKit
  import Foundation

  /// Whether this phone can still serve a card, and what leaves with it.
  ///
  /// A connected reader is a card this device can answer for. Losing it
  /// wipes the CryptoTokenKit identities that were offering that card
  /// and stops the holder advertisement so a paired requester withdraws
  /// its copy. The pairing stays: a household keeps the same peers while
  /// cards come and go.
  ///
  /// A stored NFC prime is different: the field has no lasting connected
  /// state, so the prime and the advertisement stay.
  @MainActor
  internal enum HolderCardServing {
    /// Whether a serving state has been measured this run.
    private static var didMeasure = false

    /// Last computed serving state, so an unchanged recount is silent.
    private static var wasAbleToServe = false

    /// Recomputes from the reader slot and the prime store.
    internal static func availabilityChanged() {
      guard SupportedCardTransports.offersNearField else { return }
      guard !DemoMode.shared.isActive else { return }
      let canServe =
        PrimeStore.storedCount() > 0 || CardPresence.shared.isReaderCardPresent
      if !didMeasure {
        if !canServe {
          guard CardPresence.shared.hasCompletedInitialScan else { return }
        }
        didMeasure = true
        wasAbleToServe = canServe
        if canServe {
          PhonePersistentTokenRelay.shared.start()
        } else {
          dropReaderTokens()
        }
        return
      }
      // A connected requester hears about the change at once (RAPP
      // v26.10.21 §8.4), whichever way it went; a card coupled or primed
      // again answers an earlier failure to serve.
      PhonePersistentTokenRelay.shared.cardAvailabilityChanged(servable: canServe)
      guard wasAbleToServe != canServe else {
        if canServe, !PhonePersistentTokenRelay.shared.isServing {
          PhonePersistentTokenRelay.shared.start()
        }
        return
      }
      wasAbleToServe = canServe
      if canServe {
        PhonePersistentTokenRelay.shared.start()
        return
      }
      dropReaderTokens()
    }

    /// Clears identities that belonged to a reader card.
    ///
    /// Pairing stays.
    private static func dropReaderTokens() {
      ReaderPin1Cache.shared.clear()
      wipeLocalTokens()
      PhonePersistentTokenRelay.shared.stopServing()
    }

    private static func wipeLocalTokens() {
      Task.detached(priority: .utility) {
        _ = DriverConfiguredCredentials.dropIdentityTokenConfigurations()
      }
    }
  }

#endif
