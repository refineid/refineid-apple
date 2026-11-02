// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if REFINEID_LOCAL_CARD && os(iOS)
  import CardCore
  import Foundation
  import UIKit

  /// The phone's own near field: the system slot CryptoTokenKit gives
  /// the app, the card in it, and the card session with PACE done on it.
  internal final class LiveNearField: NearField {
    /// The slot and its sheet.
    private let session: NearFieldCardSession

    internal var holdsValidCard: Bool {
      session.holdsValidCard
    }

    internal var isMissing: Bool {
      session.isMissing
    }

    internal var stateName: String {
      #if DEBUG
        session.slotState.traceName
      #else
        String(session.slotState.rawValue)
      #endif
    }

    private init(session: NearFieldCardSession) {
      self.session = session
    }

    /// Opens the slot with the sheet saying `message`, and waits for the
    /// card; a card not already on the phone is asked for with a sound.
    internal static func open(message: String) async throws -> LiveNearField {
      let opened = try await NearFieldCardSession.open(
        message: message,
        onPromptNeeded: {
          Task { @MainActor in
            UISoundLibrary.play(named: "Handoff-EncoreInfinitum")
          }
        }
      )
      return LiveNearField(session: opened)
    }

    /// The operations a fresh channel offers: PACE with the card access
    /// number done and the application selected, or, for an organization
    /// card, the plain channel each operation runs its own PACE on.
    private static func operations(
      over channel: SmartCardChannel,
      opening: NearFieldOpening
    ) -> CardOperations? {
      switch opening {
      case .cardAccessNumber(let digits):
        CardMaintenance.selectedOperations(over: channel, cardAccessNumber: digits)

      case .organizationCard:
        CardOperations(channel: channel)
      }
    }

    internal func end() {
      session.end()
    }

    internal func endChannel(_ channel: RappHeldCardChannel) {
      channel.session.end()
    }

    /// An organization card on its plain channel answers the select with
    /// `6985`, which is the card answering: only a link that gives no
    /// answer fails the keep-alive.
    internal func keepAlive(_ channel: RappHeldCardChannel) async -> Bool {
      await Task.detached(priority: .utility) {
        do {
          try channel.operations.selectFineidApplication()
          return true
        } catch  where CardOperationError.refusesBeforePace(error) {
          return true
        } catch {
          return false
        }
      }
      .value
    }

    internal func prepareChannel(_ opening: NearFieldOpening) async -> RappHeldCardChannel? {
      await withCheckedContinuation { continuation in
        DispatchQueue.global(qos: .userInitiated).async { [session] in
          guard let open = try? session.openCardSession() else {
            continuation.resume(returning: nil)
            return
          }
          OperationPhaseTrace.mark("slot-session-begun")
          guard let operations = Self.operations(over: open.channel, opening: opening) else {
            open.end()
            continuation.resume(returning: nil)
            return
          }
          OperationPhaseTrace.mark("pace-done")
          continuation.resume(
            returning: RappHeldCardChannel(session: open, operations: operations))
        }
      }
    }

    internal func show(_ text: String) {
      session.update(message: text)
    }
  }
#endif
