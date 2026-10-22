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

    /// What the sheet says for `line`.
    private static func text(_ line: NearFieldSheetLine) -> String {
      switch line {
      case .cardFound:
        String(localized: "Card found. Keep holding.")

      case .cardNotRead:
        String(localized: "The card could not be read. Hold it still and try again.")

      case .cardRead:
        String(localized: "Card read successfully.")
      }
    }

    internal func end() {
      session.end()
    }

    internal func endChannel(_ channel: RappHeldCardChannel) {
      channel.session.end()
    }

    internal func keepAlive(_ channel: RappHeldCardChannel) async -> Bool {
      await Task.detached(priority: .utility) {
        (try? channel.operations.selectFineidApplication()) != nil
      }
      .value
    }

    internal func prepareChannel(cardAccessNumber: String) async -> RappHeldCardChannel? {
      await withCheckedContinuation { continuation in
        DispatchQueue.global(qos: .userInitiated).async { [session] in
          guard let open = try? session.openCardSession() else {
            continuation.resume(returning: nil)
            return
          }
          OperationPhaseTrace.mark("slot-session-begun")
          guard
            let operations = CardMaintenance.selectedOperations(
              over: open.channel,
              cardAccessNumber: cardAccessNumber
            )
          else {
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

    internal func show(_ line: NearFieldSheetLine) {
      session.update(message: Self.text(line))
    }
  }
#endif
