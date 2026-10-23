// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CardCore
import CryptoTokenKit
import SwiftUI

/// Whether a smart card is physically in a reader right now.
///
/// Slot state is the reader's answer, read without opening any
/// session - no card I/O, nothing held, nothing another process
/// could be made to wait for. It is a different fact from the
/// token's publication: a present card can lack its token, which
/// is exactly the state the login row has to name. What this fact
/// gates is the offering of card work at all - signing a document
/// and managing PINs are not meaningful without a card under them.
@MainActor
internal final class CardPresence: ObservableObject {
  internal static let shared = CardPresence()

  /// Whether any slot reports a card, responsive or not.
  @Published internal private(set) var isCardPresent = false

  /// Whether a card is present in an external reader rather than the
  /// iPhone's temporary NFC slot.
  @Published internal private(set) var isReaderCardPresent = false {
    didSet { RemoteUseAvailability.readerCardChanged(present: isReaderCardPresent) }
  }

  /// Whether an external smart card reader hardware is connected.
  @Published internal private(set) var isReaderConnected = false

  /// Whether an external-reader card has completed system probing and
  /// is ready for a session.
  ///
  /// Presence becomes true earlier, while the slot is still `.probing`;
  /// card I/O must wait for this separate fact.
  @Published internal private(set) var isReaderCardReady = false

  /// Whether the first live slot inventory has replaced presentation
  /// hints supplied by the view that opened card management.
  @Published internal private(set) var hasCompletedInitialScan = false

  /// Whether any of those cards is on a contactless interface.
  ///
  /// Read from the slot's synthesized answer to reset, so it costs
  /// no card I/O and is known the moment the card lands on the
  /// antenna. Only this certainty makes the access-number entry
  /// appear: a contact card never needs one.
  @Published internal private(set) var isContactlessCardPresent = false

  /// The slots being watched, by name.
  private var slots: [String: TKSmartCardSlot] = [:]

  /// The reader-list observation, alive for the app's lifetime.
  private var namesObservation: NSKeyValueObservation?

  /// Per-slot state observations, keyed like `slots`.
  private var stateObservations: [String: NSKeyValueObservation] = [:]

  /// What waits for the first live slot inventory.
  private let initialScan = InitialScanGate()

  private init() {
    guard let manager = TKSmartCardSlotManager.default else {
      hasCompletedInitialScan = true
      initialScan.complete()
      return
    }
    namesObservation = manager.observe(\.slotNames, options: [.initial]) {
      [weak self] _, _ in
      Task { @MainActor [weak self] in
        self?.watchSlots()
      }
    }
  }

  /// Follows the reader list: watch every slot, forget the gone.
  private func watchSlots() {
    guard let manager = TKSmartCardSlotManager.default else { return }
    let names = Set(manager.slotNames)
    slots = slots.filter { names.contains($0.key) }
    stateObservations = stateObservations.filter { names.contains($0.key) }
    for name in names where slots[name] == nil {
      guard let slot = manager.slotNamed(name) else { continue }
      watch(slot, named: name)
    }
    recount()
    if !hasCompletedInitialScan {
      hasCompletedInitialScan = true
      #if os(iOS) && REFINEID_LOCAL_CARD
        HolderCardServing.availabilityChanged()
      #endif
      #if os(macOS)
        if isReaderCardPresent {
          PersistentTokenRegistry.shared.readerCardPresenceChanged(isReaderCardPresent: true)
        }
      #endif
      initialScan.complete()
    }
  }

  /// Runs `action` once the first live slot inventory has said whether a
  /// card is in a reader, at once when it has, or after `limit` without it;
  /// a card seen later is reported as any other.
  internal func afterInitialScan(
    atMost limit: Duration, _ action: @escaping @MainActor () -> Void
  ) {
    initialScan.wait(atMost: limit, action)
  }

  /// Watches one slot's card state.
  private func watch(_ slot: TKSmartCardSlot, named name: String) {
    slots[name] = slot
    stateObservations[name] = slot.observe(\.state, options: [.initial]) {
      [weak self] _, _ in
      Task { @MainActor [weak self] in
        self?.recount()
      }
    }
    recount()
  }

  /// A card is present when any slot says anything but "empty".
  ///
  /// A mute card counts: it is physically there, and "insert your
  /// card" would be the wrong thing to tell its holder.
  private func recount() {
    // Assigned only when it differs. A published property
    // notifies on every write, unchanged or not, and each
    // notification re-renders the window that reads this.
    let occupied = slots.filter { _, slot in
      switch slot.state {
      case .validCard, .muteCard, .probing:
        true

      default:
        false
      }
    }
    let present = !occupied.isEmpty
    let readerPresent = occupied.contains { name, _ in
      CardTransport.transport(forSlotNamed: name) == .reader
    }
    let readerReady = slots.contains { name, slot in
      CardTransport.transport(forSlotNamed: name) == .reader
        && slot.state == .validCard
    }
    let contactless = occupied.values.contains { slot in
      slot.atr.map { AnswerToReset.indicatesContactlessInterface(bytes: $0.bytes) } ?? false
    }
    // The reader's attachment is settled before a departing card is
    // reported, so a reader unplugged with its card in it reaches the
    // requester as one word: no card, no reader.
    let readerAttachmentChanged = recountReaderAttachment()
    if present != isCardPresent {
      isCardPresent = present
    }
    if contactless != isContactlessCardPresent {
      isContactlessCardPresent = contactless
    }
    if readerPresent != isReaderCardPresent {
      isReaderCardPresent = readerPresent
      #if os(iOS) && REFINEID_LOCAL_CARD
        if readerPresent {
          ReaderTokenPublication.shared.readerCardArrived()
        } else {
          ReaderTokenPublication.shared.readerCardDeparted()
        }
        HolderCardServing.availabilityChanged()
      #endif
      #if os(macOS)
        PersistentTokenRegistry.shared.readerCardPresenceChanged(isReaderCardPresent: readerPresent)
      #endif
    }
    if readerReady != isReaderCardReady {
      isReaderCardReady = readerReady
    }
    #if os(iOS) && REFINEID_LOCAL_CARD
      if readerAttachmentChanged {
        HolderCardServing.readerAttachmentChanged()
      }
    #endif
  }

  /// Follows whether a contact reader is connected; true when that
  /// changed.
  private func recountReaderAttachment() -> Bool {
    let connected = slots.keys.contains { name in
      CardTransport.transport(forSlotNamed: name) == .reader
    }
    guard connected != isReaderConnected else { return false }
    isReaderConnected = connected
    return true
  }

  #if DEBUG
    internal func setReaderCardPresentForTesting(_ present: Bool) {
      isReaderCardPresent = present
      PersistentTokenRegistry.shared.readerCardPresenceChanged(isReaderCardPresent: present)
    }
  #endif
}
