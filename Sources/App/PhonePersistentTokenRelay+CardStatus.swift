// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(iOS) && REFINEID_LOCAL_CARD
  import CardCore
  import Foundation

  /// The custodian's word on its card (RAPP v26.10.18 §8.4).
  @MainActor
  extension PhonePersistentTokenRelay {
    /// Tells the connected requester whether a card can be served (RAPP
    /// v26.10.18 §8.4); nothing is sent without a session.
    internal func reportCardStatus() {
      guard let coordinator else { return }
      let present = cardReport.present
      Task { try? await coordinator.reportCardStatus(present: present) }
    }

    /// A reader card or a prime arrived or left; a card that can be
    /// served again was coupled or primed by the holder.
    internal func cardAvailabilityChanged(servable: Bool) {
      apply(cardReport.availabilityChanged(servable: servable))
      if CardPresence.shared.isReaderCardPresent {
        prepareReaderCard()
      } else {
        Task { await RappReaderSessionHolder.shared.cardLeft() }
      }
    }

    /// Opens the reader card's session and selects the application ahead
    /// of the first request, while a requester is connected.
    internal func prepareReaderCard() {
      guard coordinator != nil, CardPresence.shared.isReaderCardPresent else { return }
      Task { await RappReaderSessionHolder.shared.prepare() }
    }

    /// Sends `word` when a transition produced one.
    internal func apply(_ word: CustodianCardReport.Word?) {
      guard word != nil else { return }
      reportCardStatus()
    }

    internal func observe(
      _ event: RappConnectionCoordinator.Event,
      connectionID: UUID
    ) {
      guard self.connectionID == connectionID else { return }
      #if DEBUG
        HolderTrace.say("session event \(eventCaseName(event))")
      #endif
      switch event {
      case .established:
        // The custodian's first word on a session is whether a card can
        // answer (RAPP v26.10.18 §8.4); the requester offers nothing
        // before it.
        operationsInFlight.removeAll()
        sessionIsIdle.withLock { $0 = true }
        sessionIdleSince.withLock { $0 = .now }
        reportCardStatus()
        prepareReaderCard()

      case .inspectPrerequisites(let operationID, _),
        .awaitUserApproval(let operationID, _),
        .executeSafeRead(let operationID, _),
        .executeCardCommand(let operationID, _):
        operationsInFlight.insert(operationID)
        sessionIsIdle.withLock { $0 = false }
        sessionIdleSince.withLock { $0 = nil }

      case .completed(let operationID, _):
        operationEnded(operationID)
        apply(cardReport.cardAnswered())

      case .terminal(let operationID?, _, let reason):
        operationEnded(operationID)
        if reason == .cardRemovedBeforeTransmit || reason == .cardCompletionAmbiguous {
          // An operation ending without the card answering means the card
          // cannot serve only when the card is truly gone. A reader card
          // still in its slot is present though one exchange glitched;
          // reporting it absent is what blanked the requester's identity
          // mid-signature. The near-field card leaves after each tap and
          // keeps the original meaning.
          if !CardPresence.shared.isReaderCardPresent {
            apply(cardReport.operationEndedUnattended())
          }
        }

      case .operationFinished(let operationID?),
        .peerUnknownOperation(let operationID?):
        operationEnded(operationID)

      case .closed:
        operationsInFlight.removeAll()
        sessionIsIdle.withLock { $0 = false }
        sessionIdleSince.withLock { $0 = nil }
        servedPairing.withLock { $0 = nil }
        Task {
          await RappReaderSessionHolder.shared.close()
          await RappNearFieldSessionHolder.shared.closeSession()
        }

      case .terminal, .operationFinished, .peerUnknownOperation, .peerBusy, .progress,
        .batchSignatures, .cardStatus:
        break
      }
    }

    internal func operationEnded(_ operationID: Data) {
      operationsInFlight.remove(operationID)
      let idle = operationsInFlight.isEmpty
      sessionIsIdle.withLock { $0 = idle }
      sessionIdleSince.withLock { $0 = idle ? .now : nil }
    }
  }
#endif
