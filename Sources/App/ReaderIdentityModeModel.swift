// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(iOS)

  import CardCore
  import Combine
  import CryptoTokenKit
  import SwiftUI

  /// Observes reader identities from the selected physical or virtual backend.
  ///
  /// A newly appearing activated reader card starts one bounded retry-counter
  /// probe for the shared health key. There is no card-presence polling.
  @MainActor
  internal final class ReaderIdentityModeModel: ObservableObject {
    // MARK: Static Computed Properties

    /// The read key a reader card carries while it has no token.
    private static let slotReadKey = "slot"

    /// Whether the platform is presenting a contact reader slot at all.
    ///
    /// A reader identity cannot exist without a reader. Asking the slot
    /// manager is a physical fact, where the token arithmetic below is
    /// an inference -- and an inference with a window in it: `ctkd`
    /// publishes a freshly minted NFC token before `registerSmartCard`
    /// has put it in the persistent list, so for a second after every
    /// setup that token looks exactly like a reader token. That window
    /// is what flashed a USB-C reader screen at a holder who had no
    /// reader attached.
    ///
    /// The built-in NFC slot exists only while a session is open and
    /// carries "NFC" in its name; a reader slot carries the reader's.
    private static var hasReaderSlot: Bool {
      guard let manager = TKSmartCardSlotManager.default else { return false }
      return manager.slotNames.contains { name in
        CardTransport.transport(forSlotNamed: name) == .reader
      }
    }

    // MARK: Properties

    /// The live reader tokens by identifier, including ones minted
    /// before this build, in a stable order.
    ///
    /// Named rather than counted: each identifier is one this model has
    /// already proved live and reader-backed, which is what makes it
    /// safe to ask the keychain about. A broad token search is active
    /// on iOS - it was measured opening a "Ready to Scan" sheet - and
    /// what wakes the field is a registered token that has to be minted
    /// to answer at all. A token already live answers from what it
    /// published.
    @Published internal private(set) var liveReaderTokenIdentifiers: [String] = []

    /// Monotonically increasing revision of the reader tokens.
    @Published internal private(set) var generation = 0

    /// Whether the reader slot holds a card the system reports ready,
    /// read from the slot itself rather than inferred from a token.
    @Published internal private(set) var readerCardIsReady = false

    /// The slot observation, alive for the model's lifetime.
    private var readinessObservation: AnyCancellable?

    /// Watches physical token publication and removal.
    private let watcher = TKTokenWatcher()

    /// Session-only health shared by every PIN-management shortcut.
    private let retryHealth = CredentialRetryHealth.shared

    /// One-shot removal handlers already installed for token IDs.
    private var removalHandlers: Set<String> = []

    // MARK: Computed Properties

    /// Number of live reader tokens.
    internal var liveReaderTokenCount: Int {
      if DemoMode.shared.isActive {
        return DemoMode.shared.isReaderCardPresent ? 1 : 0
      }
      return liveReaderTokenIdentifiers.count
    }

    /// Whether an inserted reader card published the authoritative empty
    /// token that means its factory credentials still require activation.
    internal var hasActivationRequiredCard: Bool {
      if DemoMode.shared.isActive {
        return DemoMode.shared.isReaderCardPresent
          && DemoMode.shared.activationNeeds.any
      }
      return liveReaderTokenIdentifiers.contains(
        where: ActivationTokenIdentity.recognizes(tokenID:)
      )
    }

    /// Whether the setup form must be replaced by reader identity controls.
    internal var isActive: Bool {
      if DemoMode.shared.isActive {
        return DemoMode.shared.isReaderCardPresent
      }
      return !liveReaderTokenIdentifiers.isEmpty || readerCardIsReady
    }

    /// Changes whenever the identities rendered by the shared reader view change.
    internal var holderReadKey: [String] {
      if DemoMode.shared.isActive {
        return isActive ? [DemoMode.shared.holderName] : []
      }
      if liveReaderTokenIdentifiers.isEmpty {
        return readerCardIsReady ? [Self.slotReadKey + ":\(generation)"] : []
      }
      return liveReaderTokenIdentifiers.map { "\($0):\(generation)" }
    }

    // MARK: Lifecycle

    internal init() {
      if !DemoMode.shared.isActive {
        watcher.setInsertionHandler(Self.insertionHandler(for: self))
        readinessObservation = CardPresence.shared.$isReaderCardReady
          .receive(on: DispatchQueue.main)
          .sink { [weak self] ready in
            self?.readerCardReadinessChanged(ready)
          }
      }
    }

    // MARK: Static Functions

    /// Builds a ctkd callback with no inherited main-actor isolation.
    ///
    /// `TKTokenWatcher` invokes this block on its XPC queue. Constructing the
    /// block directly inside this main-actor type makes Swift trap before its
    /// body can enqueue the intended actor hop.
    nonisolated private static func insertionHandler(
      for model: ReaderIdentityModeModel
    ) -> @Sendable (String) -> Void {
      { [weak model] tokenIdentifier in
        guard CardTokenNamespace.owns(tokenIdentifier: tokenIdentifier) else {
          return
        }
        Task { @MainActor [weak model] in
          model?.refresh()
        }
      }
    }

    /// Builds a ctkd removal callback without main-actor isolation.
    nonisolated private static func removalHandler(
      for model: ReaderIdentityModeModel
    ) -> @Sendable (String) -> Void {
      { [weak model] removedTokenIdentifier in
        Task { @MainActor [weak model] in
          model?.tokenWasRemoved(removedTokenIdentifier)
        }
      }
    }

    /// The names the published tokens carry.
    private static func publishedNames(_ identifiers: [String]) async -> [String] {
      await Task.detached(priority: .utility) {
        identifiers.compactMap { identifier in
          PublishedIdentityName.name(ofTokenIdentifier: identifier)
        }
      }.value
    }

    #if REFINEID_LOCAL_CARD
      /// The holder's name read straight off the card in a reader, for a
      /// card the system has published no token for.
      ///
      /// A contact reader reaches the card without PACE, so no card access
      /// number is needed. Only reader slots are tried: the contactless
      /// face of a dual-interface reader would need one. The session is
      /// held for the read alone.
      nonisolated private static func holderNameFromReader() async -> String? {
        guard let manager = TKSmartCardSlotManager.default else { return nil }
        let cards = await CardSlotSearch.allOccupied(in: manager)
          .filter { CardTransport.transport(forSlotNamed: $0.name) == .reader }
          .compactMap { $0.slot.makeSmartCard().map(CardMaintenance.UncheckedCard.init) }
        guard !cards.isEmpty else { return nil }
        return await withCheckedContinuation { continuation in
          DispatchQueue.global(qos: .userInitiated).async {
            for card in cards {
              if let name = Self.holderName(on: card) {
                continuation.resume(returning: name)
                return
              }
            }
            continuation.resume(returning: nil)
          }
        }
      }

      /// One card's holder name, or nil when it could not be read.
      nonisolated private static func holderName(on card: CardMaintenance.UncheckedCard) -> String?
      {
        let read: String?? = try? SmartCardChannel(card.card).withSession { channel in
          let operations = CardOperations(channel: channel)
          try operations.selectFineidApplication()
          return DistinguishedName.holderLine(
            fromCertificate: try operations.readCertificate(.authentication))
        }
        return read.flatMap(\.self)
      }
    #endif

    // MARK: Functions

    /// Returns holder names without exposing the backend to the view.
    ///
    /// A published token names the holder from what it published. A
    /// reader card without one is read directly: the slot is the fact
    /// that a card is there, and a token is only the shortcut to it.
    internal func holderNames() async -> [String] {
      if DemoMode.shared.isActive {
        return isActive ? [DemoMode.shared.holderName] : []
      }
      if !liveReaderTokenIdentifiers.isEmpty {
        return await Self.publishedNames(liveReaderTokenIdentifiers)
      }
      guard readerCardIsReady else { return [] }
      #if REFINEID_LOCAL_CARD
        // The system may still be minting the card's token; a read now
        // would take the card from under it. Wait that out, and use the
        // token if it arrived. The watcher is read directly: `refresh`
        // moves the read key, which would start this read over.
        await ReaderTokenPublication.shared.awaitPublication()
        let published = watcher.tokenIDs.filter(CardTokenNamespace.owns(tokenIdentifier:)).sorted()
        if !published.isEmpty {
          return await Self.publishedNames(published)
        }
        return await Self.holderNameFromReader().map { [$0] } ?? []
      #else
        return []
      #endif
    }

    /// Lists live reader tokens when a reader slot is present.
    internal func refresh() {
      generation &+= 1
      if DemoMode.shared.isActive {
        liveReaderTokenIdentifiers = []
        return
      }
      guard Self.hasReaderSlot else {
        let hadReaderTokens = !liveReaderTokenIdentifiers.isEmpty
        if hadReaderTokens {
          retryHealth.clear()
          #if REFINEID_LOCAL_CARD
            ReaderPin1Cache.shared.clear()
          #endif
        }
        liveReaderTokenIdentifiers = []
        return
      }
      let refineIDTokenIdentifiers =
        watcher.tokenIDs.filter(CardTokenNamespace.owns(tokenIdentifier:)).sorted()

      let cardAppearanceChanged =
        refineIDTokenIdentifiers != liveReaderTokenIdentifiers
      liveReaderTokenIdentifiers = refineIDTokenIdentifiers

      if cardAppearanceChanged {
        if liveReaderTokenIdentifiers.isEmpty {
          #if REFINEID_LOCAL_CARD
            ReaderPin1Cache.shared.clear()
          #endif
        }
        if liveReaderTokenIdentifiers.isEmpty || hasActivationRequiredCard {
          retryHealth.clear()
        } else {
          retryHealth.refreshFromReader()
        }
      }

      for tokenIdentifier in liveReaderTokenIdentifiers {
        observeRemoval(of: tokenIdentifier)
      }
    }

    /// Refreshes the UI when one physical token leaves.
    private func observeRemoval(of tokenIdentifier: String) {
      guard removalHandlers.insert(tokenIdentifier).inserted else { return }
      watcher.addRemovalHandler(
        Self.removalHandler(for: self),
        forTokenID: tokenIdentifier
      )
    }

    /// Applies one removal only after the callback has reached the main actor.
    private func tokenWasRemoved(_ tokenIdentifier: String) {
      removalHandlers.remove(tokenIdentifier)
      refresh()
    }

    /// The slot's word on the reader card changed.
    private func readerCardReadinessChanged(_ ready: Bool) {
      guard ready != readerCardIsReady else { return }
      readerCardIsReady = ready
      generation &+= 1
      if !ready, liveReaderTokenIdentifiers.isEmpty {
        retryHealth.clear()
        #if REFINEID_LOCAL_CARD
          ReaderPin1Cache.shared.clear()
        #endif
      }
    }
  }

#endif
