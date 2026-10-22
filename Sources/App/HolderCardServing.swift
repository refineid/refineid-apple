// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(iOS) && REFINEID_LOCAL_CARD

  import CardCore
  import CryptoTokenKit
  import Foundation

  /// What the card this phone holds does to serving.
  ///
  /// Serving does not wait for a card: while Remote Access is on and a
  /// computer is paired, the phone stays reachable and tells the computer
  /// which card it holds, none included (RAPP v26.10.22 §8.4 item 1), so
  /// the computer can ask for the card instead of pairing again. A reader
  /// card that leaves takes the CryptoTokenKit identities offering it and
  /// a held PIN 1 with it; the pairing and the session stay.
  @MainActor
  internal enum HolderCardServing {
    /// Whether a card has been measured this run.
    private static var didMeasure = false

    /// Whether the phone held a card when last measured, so an unchanged
    /// recount is silent.
    private static var heldCard = false

    /// Recomputes from the reader slot and the prime store.
    internal static func availabilityChanged() {
      guard SupportedCardTransports.offersNearField else { return }
      guard !DemoMode.shared.isActive else { return }
      let holdsCard =
        PrimeStore.storedCount() > 0 || CardPresence.shared.isReaderCardPresent
      if !didMeasure {
        if !holdsCard {
          guard CardPresence.shared.hasCompletedInitialScan else { return }
        }
        didMeasure = true
        heldCard = holdsCard
        if !holdsCard {
          dropReaderTokens()
        }
        PhonePersistentTokenRelay.shared.start()
        return
      }
      // A connected requester hears about the change at once (RAPP
      // v26.10.22 §8.4 item 1), whichever way it went.
      PhonePersistentTokenRelay.shared.cardAvailabilityChanged()
      if !PhonePersistentTokenRelay.shared.isServing {
        PhonePersistentTokenRelay.shared.start()
      }
      guard heldCard != holdsCard else { return }
      heldCard = holdsCard
      if !holdsCard {
        dropReaderTokens()
      }
    }

    /// A contact card reader was attached or detached: every requester
    /// hears it (RAPP v26.10.22 §8.4 item 1, CC-81).
    ///
    /// The card that left with a detached reader was reported as it left.
    internal static func readerAttachmentChanged() {
      guard SupportedCardTransports.offersNearField else { return }
      guard !DemoMode.shared.isActive else { return }
      PhonePersistentTokenRelay.shared.reportCardStatus()
    }

    /// Clears identities that belonged to a reader card.
    ///
    /// Pairing and serving stay.
    private static func dropReaderTokens() {
      HeldPin1.shared.clear()
      wipeLocalTokens()
    }

    private static func wipeLocalTokens() {
      Task.detached(priority: .utility) {
        _ = DriverConfiguredCredentials.dropIdentityTokenConfigurations()
      }
    }
  }

#endif
