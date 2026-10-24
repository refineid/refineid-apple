// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if REFINEID_LOCAL_CARD && os(iOS)

  import CardCore
  import CryptoTokenKit
  import Foundation

  /// One hold of the card against the phone's own antenna: the system NFC
  /// slot, the live card in it, and the single line of text the holder can
  /// read while the system sheet is up.
  ///
  /// `update(message:)` is the ONLY instruction that reaches the holder
  /// once the sheet is presented -- there is no app UI in front of it --
  /// so every step of a flow built on this type says what it is doing
  /// through it.
  ///
  /// Opening the slot is retried while the system answers "busy" or with
  /// the reader's pause after a field (``NearFieldSlotRequest``). `nfcd`
  /// releases the radio asynchronously after a previous hold, so a second
  /// attempt shortly after a first is normal rather than exceptional; a
  /// Busy answer costs about 2.5 seconds by itself, which is why the
  /// retry budget is counted in attempts and not in a deadline.
  ///
  /// The card is only usable inside its exclusive session: a sessionless
  /// `TKSmartCard.transmit` on the Built-in NFC Slot is parked by `ctkd`
  /// forever -- it neither answers nor fails. This type therefore hands
  /// out no bare card. Card I/O goes through ``withCardSession(_:)``,
  /// which begins the session before the first APDU.
  ///
  /// Ending is asymmetric on purpose, and ``isMissing`` is what says so.
  /// The app's own hold may end when its work is done, but a session held
  /// across a system-driven mint must be released only when the slot is
  /// genuinely `.missing`: releasing it on any other non-`validCard`
  /// state was measured tearing a signature down part way through a read.
  ///
  /// Provenance: `SafariIdentityPrime.openOneSystemNFCSession`,
  /// `createSystemRegistrationSlot`, `isBusyNFCError` and
  /// `waitForSmartCard` in the donor
  /// `platform/apple/RefineID/Local/SafariIdentityPrime+OneSystemNFC.swift`
  /// and `SafariIdentityPrime+SystemSlot.swift`.
  ///
  /// `@unchecked Sendable` is the deliberate bridge across CryptoTokenKit:
  /// the slot and the card are not `Sendable`, they are stored once at
  /// init and never reassigned, and the one place two threads could touch
  /// the slot at the same time -- the arrival watch -- keeps it behind a
  /// lock.
  internal final class NearFieldCardSession: @unchecked Sendable {
    /// Why a hold never reached a live card.
    internal enum Failure: Error, Equatable {
      /// The radio was still busy after every retry.
      case antennaBusy

      /// The slot opened but no card ever became valid in it.
      case cardNeverArrived

      /// The holder closed the system sheet before presenting a card.
      case dismissed

      /// `nfcd` has paused reader mode to let the radio cool, and will not
      /// open a slot until the pause lifts on its own.
      case readerCoolingDown

      /// The system would not give this app an NFC slot at all.
      case slotRefused
    }

    /// The slot, and the card once it arrives, behind a lock.
    ///
    /// The state observer is `@Sendable` and runs on whatever queue
    /// CryptoTokenKit chooses, while the polling task reads the same
    /// values; neither `TKSmartCardSlot` nor `TKSmartCard` is `Sendable`,
    /// so both live in here and are touched only under the lock.
    private final class Arrival: @unchecked Sendable {
      private let lock = NSLock()
      private let slot: TKSmartCardSlot
      private var card: TKSmartCard?

      init(slot: TKSmartCardSlot) {
        self.slot = slot
      }

      /// The card, taken from the slot the first time the slot reports a
      /// valid one, and the same card on every later call.
      func take() -> TKSmartCard? {
        lock.lock()
        defer { lock.unlock() }
        if card == nil, slot.state == .validCard {
          card = slot.makeSmartCard()
        }
        return card
      }
    }

    /// How a wait for the card ended.
    private enum Arrived {
      /// A live card is in the slot.
      case arrived(TKSmartCard)

      /// The holder closed the sheet.
      case dismissed

      /// The wait ran out with the sheet still up.
      case neverArrived
    }

    /// How many times the slot is polled for a card before giving up.
    private static let arrivalPollLimit: Int = 200

    /// Wait between two looks at the slot.
    private static let arrivalPollInterval: Duration = .milliseconds(100)

    /// Number of arrival poll cycles before notifying that a prompt is needed.
    private static let promptPollThreshold: Int = 5

    /// The card in the slot, reachable only inside its session.
    private let card: TKSmartCard

    /// The slot the card is in, for its state and its answer to reset.
    private let slot: TKSmartCardSlot

    /// The system NFC session, which owns the sheet the holder sees.
    private let session: TKSmartCardSlotNFCSession

    /// The card's answer to reset, empty when the slot reports none.
    ///
    /// This is what names the card for the prime store, so a slot that
    /// answers nothing must be refused rather than folded into a shared
    /// identifier.
    internal var answerToReset: Data {
      slot.atr?.bytes ?? Data()
    }

    /// Whether the slot still holds a valid card right now.
    internal var holdsValidCard: Bool {
      slot.state == .validCard
    }

    /// The slot's state right now.
    internal var slotState: TKSmartCardSlot.State {
      slot.state
    }

    /// Whether the slot is empty right now.
    internal var isSlotMissing: Bool {
      slot.state == .missing
    }

    /// Whether the slot is gone for good: the one state that means a held
    /// session is safe to release; any other non-`validCard` state can be
    /// a card that is still there and still answering.
    internal var isMissing: Bool {
      slot.state == .missing
    }

    /// Whether the user had to be prompted because the card was not already in place.
    internal let wasPrompted: Bool

    private init(
      session: TKSmartCardSlotNFCSession,
      slot: TKSmartCardSlot,
      card: TKSmartCard,
      wasPrompted: Bool
    ) {
      self.session = session
      self.slot = slot
      self.card = card
      self.wasPrompted = wasPrompted
    }

    /// Opens the system NFC slot and waits for a live card in it, the
    /// sheet showing the meter of `operation` with no step reached.
    ///
    /// The returned session owns the sheet until ``end()``.
    internal static func open(showing operation: NearFieldOperation) async throws
      -> NearFieldCardSession
    {
      try await open(message: NearFieldSheet.opening(operation), onPromptNeeded: nil)
    }

    /// Opens the system NFC slot and waits for a live card in it, invoking
    /// `onPromptNeeded` if the card is not already resting under the device.
    internal static func open(
      message: String,
      onPromptNeeded: (@Sendable () -> Void)?
    ) async throws -> NearFieldCardSession {
      #if DEBUG
        HolderTrace.say("NearFieldCardSession.open: opening slot with message '\(message)'")
      #endif
      guard PrimeStore.markRegistrationField() else {
        throw Failure.slotRefused
      }
      do {
        guard let manager = TKSmartCardSlotManager.default else {
          #if DEBUG
            HolderTrace.say("NearFieldCardSession.open: TKSmartCardSlotManager.default is nil")
          #endif
          throw Failure.slotRefused
        }
        let opened = try await openSlot(manager: manager, message: message)
        guard let openedName = opened.slotName,
          let openedSlot = manager.slotNamed(openedName)
        else {
          #if DEBUG
            HolderTrace.say(
              "NearFieldCardSession.open: slot '\(opened.slotName ?? "nil")' not found in manager"
            )
          #endif
          opened.end()
          throw Failure.slotRefused
        }
        #if DEBUG
          HolderTrace.say(
            "NearFieldCardSession.open: slot '\(openedName)' opened, waiting for card"
          )
        #endif
        let (arrived, prompted) = await Self.waitForCard(
          in: openedSlot,
          named: openedName,
          from: manager,
          onPromptNeeded: onPromptNeeded
        )
        return try Self.resolveArrival(
          arrived,
          prompted: prompted,
          session: opened,
          slot: openedSlot
        )
      } catch {
        PrimeStore.clearRegistrationField()
        throw error
      }
    }

    private static func resolveArrival(
      _ arrived: Arrived,
      prompted: Bool,
      session: TKSmartCardSlotNFCSession,
      slot: TKSmartCardSlot
    ) throws -> NearFieldCardSession {
      switch arrived {
      case .arrived(let live):
        return Self(session: session, slot: slot, card: live, wasPrompted: prompted)

      case .dismissed:
        session.end()
        throw Failure.dismissed

      case .neverArrived:
        session.end()
        throw Failure.cardNeverArrived
      }
    }

    /// Waits for the slot to hold a valid card, or gives up.
    ///
    /// Both arrival mechanisms are needed. The state observer reports the
    /// card the instant the slot validates it, which is as early as it
    /// can be known; the poll covers a transition that lands before the
    /// observer is installed, and a slot that reaches `validCard` without
    /// ever notifying.
    ///
    /// The poll also watches for the slot leaving the manager, which is
    /// what a dismissed sheet looks like from here: `ctkd` takes the slot
    /// away with the panel, and nothing else tells us. Without that check
    /// a holder who cancels waits out the entire arrival budget -- twenty
    /// seconds of a flow that is already over, with its sound still
    /// running.
    private static func waitForCard(
      in openedSlot: TKSmartCardSlot,
      named slotName: String,
      from manager: TKSmartCardSlotManager,
      onPromptNeeded: (@Sendable () -> Void)?
    ) async -> (Arrived, Bool) {
      let arrival = Arrival(slot: openedSlot)
      let observation = openedSlot.observe(\.state, options: [.initial, .new]) { slot, _ in
        #if DEBUG
          HolderTrace.say("waitForCard: slot state \(slot.state.traceName)")
        #endif
        _ = arrival.take()
      }
      defer { observation.invalidate() }
      var cardPrompted = false
      for attempt in 1...Self.arrivalPollLimit {
        if let found = arrival.take() {
          return (.arrived(found), cardPrompted)
        }
        guard manager.slotNames.contains(slotName) else {
          return (.dismissed, cardPrompted)
        }
        if attempt == Self.promptPollThreshold, !cardPrompted {
          cardPrompted = true
          onPromptNeeded?()
        }
        try? await Task.sleep(for: Self.arrivalPollInterval)
      }
      if let found = arrival.take() {
        return (.arrived(found), cardPrompted)
      }
      return (.neverArrived, cardPrompted)
    }

    /// Replaces the line of text on the system sheet.
    ///
    /// A refused update is not worth failing a hold over: the card is
    /// still there and the work can still finish, the holder just reads a
    /// staler sentence.
    internal func update(message: String) {
      try? session.update(message: message)
    }

    /// The meter of `operation` on this hold's sheet, with the card found
    /// and the secure channel running.
    internal func meter(_ operation: NearFieldOperation) -> NearFieldSheet {
      let sheet = NearFieldSheet(operation) { [self] text in update(message: text) }
      sheet.reach(.secureChannel)
      return sheet
    }

    /// Ends the hold and dismisses the system sheet.
    internal func end() {
      PrimeStore.clearRegistrationField()
      session.end()
    }

    /// Runs `body` inside the card's exclusive session, near-field budget.
    internal func withCardSession<Value>(
      _ body: (SmartCardChannel) throws -> Value
    ) throws -> Value {
      try withCardSession(waits: .nearField, body)
    }

    /// Runs `body` inside the card's exclusive session with an explicit wait budget.
    internal func withCardSession<Value>(
      waits: SmartCardChannel.ResponseWait,
      _ body: (SmartCardChannel) throws -> Value
    ) throws -> Value {
      try SmartCardChannel(card, waits: waits).withSession(body)
    }

    /// The card's exclusive session, open until its owner ends it.
    internal func openCardSession() throws -> SmartCardChannel.OpenSession {
      try SmartCardChannel(card, waits: .nearField).openSession()
    }

    deinit {
      PrimeStore.clearRegistrationField()
    }
  }

#endif
