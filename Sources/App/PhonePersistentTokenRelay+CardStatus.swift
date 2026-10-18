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
        reportCardStatus()

      case .inspectPrerequisites(let operationID, _),
        .awaitUserApproval(let operationID, _),
        .executeSafeRead(let operationID, _),
        .executeCardCommand(let operationID, _):
        operationsInFlight.insert(operationID)
        sessionIsIdle.withLock { $0 = false }

      case .completed(let operationID, _):
        operationEnded(operationID)
        apply(cardReport.cardAnswered())

      case .terminal(let operationID?, _, let reason):
        operationEnded(operationID)
        if reason == .cardRemovedBeforeTransmit || reason == .cardCompletionAmbiguous {
          // The card did not answer: the custodian's own evidence that it
          // cannot serve right now, until the holder couples it again.
          apply(cardReport.operationEndedUnattended())
        }

      case .operationFinished(let operationID?),
        .peerUnknownOperation(let operationID?):
        operationEnded(operationID)

      case .closed:
        operationsInFlight.removeAll()
        sessionIsIdle.withLock { $0 = false }

      case .terminal, .operationFinished, .peerUnknownOperation, .peerBusy, .progress,
        .batchSignatures, .cardStatus:
        break
      }
    }

    internal func operationEnded(_ operationID: Data) {
      operationsInFlight.remove(operationID)
      let idle = operationsInFlight.isEmpty
      sessionIsIdle.withLock { $0 = idle }
    }
  }
#endif
