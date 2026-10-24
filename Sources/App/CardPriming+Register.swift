// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if REFINEID_LOCAL_CARD && os(iOS)

  import CardCore
  import CryptoTokenKit
  import Foundation

  /// Registering the live card so the system can ask for it later.
  ///
  /// Kept with the card in the slot: `registerSmartCard` accepts only a
  /// token created for a live slot, so a registration attempted after
  /// the hold ends finds nothing to register.
  extension CardPriming {
    /// Registers the live card so the system can ask for it later.
    internal static func register(
      instance: CardInstanceIdentifier,
      session: NearFieldCardSession
    ) async -> Bool {
      await MainActor.run { HolderCardServing.availabilityChanged() }
      let manager = TKSmartCardTokenRegistrationManager.default
      let tokenID = await Self.tokenID(for: instance, session: session)
      if manager.registeredSmartCardTokens.contains(tokenID) {
        return true
      }
      for _ in 1...Self.registrationAttemptLimit {
        guard session.holdsValidCard else {
          return false
        }
        do {
          try manager.registerSmartCard(
            tokenID: tokenID, promptMessage: Self.registrationPrompt)
          return true
        } catch {
          // CryptoTokenKit may publish while the throwing call unwinds;
          // already registered is also success for this idempotent action.
          if manager.registeredSmartCardTokens.contains(tokenID) {
            return true
          }
        }
      }
      return false
    }

    /// The token id to register, preferring the one the system already
    /// publishes for this card.
    ///
    /// `ctkd` mints the token from the prime store moments after the
    /// prime is written, so the watcher is asked a few times before the
    /// id is constructed from the class id instead. The constructed form
    /// is the same string the system uses, so it registers the same
    /// token; it just cannot be confirmed first.
    internal static func tokenID(
      for instance: CardInstanceIdentifier,
      session: NearFieldCardSession
    ) async -> String {
      let watcher = TKTokenWatcher()
      let expected = CardTokenNamespace.tokenIdentifier(for: instance)
      for _ in 1...Self.tokenPollLimit {
        if let published = watcher.tokenIDs.first(where: { tokenID in tokenID == expected }) {
          return published
        }
        guard session.holdsValidCard else { break }
        try? await Task.sleep(for: Self.tokenPollInterval)
      }
      return expected
    }
  }

#endif
