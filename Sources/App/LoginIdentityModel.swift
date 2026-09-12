// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS)

  import CardCore
  import CryptoTokenKit
  import os.log
  import SwiftUI

  /// Whether the system has a RefineID login identity to offer right now.
  ///
  /// Identity availability comes exclusively from token events; this model
  /// never polls the card. The earlier failure mode was an event-engine bug
  /// that repeatedly rebuilt watchers and queried state, continuously
  /// contending with `ctkd` until Safari authentication stalled. A separate
  /// health model may perform one bounded retry-counter probe after a ready
  /// event, but neither model loops while waiting for a card.
  ///
  /// `TKTokenWatcher` reports what `ctkd` has already published, so the
  /// availability answer stays live: a card arriving or leaving moves it
  /// without polling or anyone pressing refresh.
  @MainActor
  @Observable
  internal final class LoginIdentityModel {
    /// What the login row can truthfully say.
    internal enum Availability: Equatable {
      /// A card is in the reader but no identity is offered from it
      /// - the state after a driver update, until the card is seen
      /// again.
      case cardWithoutIdentity

      /// No card in any reader.
      case noCard

      /// An identity is published and Safari can be offered it.
      case ready
    }

    #if DEBUG
      /// Watcher outcomes, in development builds only.
      ///
      /// Counts and booleans, never an identifier. A production
      /// build writes no diagnostics.
      private static let log = Logger(
        subsystem: "fi.refineid.ReFineID", category: "login-identity"
      )
    #endif

    /// The one instance, built once for the process.
    ///
    /// Not a `@State` default. SwiftUI evaluates a `@State` default
    /// expression on every `init` of the view that declares it -
    /// which is every re-render - and keeps only the first. Building
    /// this model there meant every re-render ran a keychain query
    /// and installed another `TKTokenWatcher` handler, and those
    /// handlers fired refreshes that caused more re-renders. Measured
    /// on 2026-08-04 at about nine hundred keychain queries a second,
    /// which starved `ctkd` and blocked other applications' card use:
    /// Adobe Acrobat hung for thirty-five seconds inside
    /// CryptoTokenKit waiting for a session this app was crowding
    /// out.
    internal static let shared = LoginIdentityModel()

    /// The credential entry the app itself publishes, which the
    /// system lists as a token without it ever being a card.
    private static let credentialEntryPrefix =
      CardTokenNamespace.tokenPrefix
      + DriverConfiguredCredentials.configurationInstanceID

    /// Watches publication and removal.
    ///
    /// No card I/O of any kind.
    private let watcher = TKTokenWatcher()

    /// The recovery attempt in flight, if any.
    @ObservationIgnored private var recovery: Task<Void, Never>?

    /// Whether recovery was already tried for this card appearance.
    @ObservationIgnored private var attempted = false

    /// Token ids already given a removal handler, so each is asked once.
    private var observed: Set<String> = []

    /// Owned identities last reported, so a listing that did not move
    /// does not rebuild the login row.
    internal private(set) var ownedTokenIDs: Set<String> = []

    /// Whether Safari can be offered an identity from this card.
    internal private(set) var isReady = false

    /// Counts the refreshes, so a row that keys on it re-reads what
    /// it shows whenever the token listing moves - a re-mint after a
    /// driver update changes what a name read answers without ever
    /// changing `isReady`.
    internal private(set) var generation = 0

    internal init() {
      watcher.setInsertionHandler(Self.insertionHandler(for: self))
      refresh()
    }

    /// Combines publication with whether a card or a paired holder is
    /// actually here.
    ///
    /// A leftover token from an earlier run is not a person on this
    /// window.
    nonisolated internal static func resolved(
      tokenPublished: Bool,
      cardPresent: Bool,
      holderAdvertising: Bool,
      hasBorrowedCertificate: Bool
    ) -> Availability {
      let hasLiveSource = cardPresent || holderAdvertising
      let hasIdentity = tokenPublished || hasBorrowedCertificate
      if hasLiveSource, hasIdentity {
        return .ready
      }
      if hasLiveSource {
        return .cardWithoutIdentity
      }
      return .noCard
    }

    /// Builds a `ctkd` callback with no inherited main-actor isolation.
    ///
    /// `TKTokenWatcher` invokes this on its own XPC queue. Constructing
    /// the block inside this main-actor type makes Swift trap before the
    /// body can hop to the intended actor.
    nonisolated private static func insertionHandler(
      for model: LoginIdentityModel
    ) -> @Sendable (String) -> Void {
      { [weak model] _ in
        Task { @MainActor [weak model] in
          model?.refresh()
        }
      }
    }

    /// The same, for a token going away.
    nonisolated private static func removalHandler(
      for model: LoginIdentityModel
    ) -> @Sendable (String) -> Void {
      { [weak model] removed in
        Task { @MainActor [weak model] in
          model?.observed.remove(removed)
          model?.refresh()
        }
      }
    }

    /// The software shape of pulling the card: begin one session on
    /// each present card and end it at once.
    nonisolated private static func touchPresentCard() async {
      guard let manager = TKSmartCardSlotManager.default else { return }
      for name in manager.slotNames {
        guard
          let slot = manager.slotNamed(name),
          slot.state == .validCard,
          let card = slot.makeSmartCard()
        else { continue }
        // Ending a session that never began trips an assertion inside
        // TKSmartCard, which raises an exception nothing catches and
        // takes the process with it. The card can leave between the
        // state read above and this call, so the session is ended only
        // when the card says it opened one.
        let offers = SmartCardProtocolNegotiation.offers(
          answerToReset: slot.atr?.bytes)
        for (offset, protocols) in offers.enumerated() {
          card.allowedProtocols = protocols
          do {
            guard try await card.beginSession() else { break }
            card.endSession()
            break
          } catch {
            let hasNarrowerOffer = offset + 1 < offers.count
            guard
              hasNarrowerOffer,
              SmartCardProtocolNegotiation.retries(after: error)
            else { break }
          }
        }
      }
    }

    /// Re-reads what is published and keeps watching what is there.
    ///
    /// The model's own watcher is the source: it is connected and
    /// event-fed, so its listing is current at every call. A watcher
    /// built fresh for the question answers empty until its connection
    /// comes up - which at launch, with the card already in the
    /// reader, is exactly when the question is asked.
    internal func refresh() {
      let listed = watcher.tokenIDs
      // The credential entry and a displaced remote-card registration
      // are both listed without a card being present, so neither may
      // answer for one.
      let owned = listed.filter { identifier in
        PersistentTokenIdentity.owns(tokenIdentifier: identifier)
          || (CardTokenNamespace.owns(tokenIdentifier: identifier)
            && !identifier.hasPrefix(Self.credentialEntryPrefix)
            && !CardTokenNamespace.isDisplacedRemoteCardToken(tokenIdentifier: identifier))
      }
      let ready = !owned.isEmpty
      let nextOwned = Set(owned)
      if ready != isReady || nextOwned != ownedTokenIDs {
        generation += 1
      }
      isReady = ready
      ownedTokenIDs = nextOwned
      #if DEBUG
        Self.log.info(
          "refresh: \(listed.count) listed, ready \(self.isReady)"
        )
      #endif
      for identifier in owned {
        guard observed.insert(identifier).inserted else { continue }
        watcher.addRemovalHandler(Self.removalHandler(for: self), forTokenID: identifier)
      }
    }

    /// Performs one software "reinsertion" for this card appearance.
    ///
    /// The no-card-I/O rule above has exactly one exception, taken
    /// only in the state it exists to prevent: a card in the reader
    /// with no identity published from it. Pulling the card is what
    /// recovers that state, because the card-status change makes
    /// `ctkd` ask the driver again - and opening one brief session
    /// and closing it produces the same status change in software.
    /// It runs only while nothing is published, so there is no token
    /// whose signature could be made to wait, and once per
    /// appearance, so a card the driver genuinely cannot serve is
    /// not prodded forever.
    internal func attemptRecovery() async {
      guard !attempted, recovery == nil, !isReady else { return }
      attempted = true
      let task = Task { await Self.touchPresentCard() }
      recovery = task
      await task.value
      guard !task.isCancelled, !Task.isCancelled else { return }
      recovery = nil
      refresh()
    }

    /// Stops any scheduled recovery; a card that left resets the
    /// once-per-appearance budget.
    internal func cancelRecovery(cardLeft: Bool) {
      recovery?.cancel()
      recovery = nil
      if cardLeft {
        attempted = false
      }
    }
  }

#endif
