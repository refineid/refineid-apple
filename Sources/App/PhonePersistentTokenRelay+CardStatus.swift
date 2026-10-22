// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(iOS) && REFINEID_LOCAL_CARD
  import CardCore
  import Foundation
  import RappEngine

  /// The custodian's word on its card (RAPP v26.10.21 §8.4).
  @MainActor
  extension PhonePersistentTokenRelay {
    /// The authentication certificate of the card this phone serves: the
    /// reader card's once read, else the primed near-field card's.
    private var servedCertificate: Data? {
      if CardPresence.shared.isReaderCardPresent {
        return readerCertificate
      }
      return PrimeStore.storedIdentities().first?.certDER
    }

    /// Which card the phone can serve now: present only while a card can
    /// answer and its authentication certificate is known, so the
    /// requester can tell which card it is (§8.4 items 1 and 2).
    internal var cardStatus: RappCardStatus {
      guard cardReport.present,
        let fingerprint = servedCertificate.flatMap(RappCertificateFingerprint.init(certificate:))
      else { return .absent }
      return .present(fingerprint)
    }

    /// Tells the connected requester which card can answer, when that
    /// changed since it was last told on this session; nothing is sent
    /// without a session.
    internal func reportCardStatus() {
      guard let coordinator else { return }
      let status = cardStatus
      guard status != reportedCardStatus else { return }
      reportedCardStatus = status
      Task { try? await coordinator.reportCardStatus(status) }
    }

    /// A reader card or a prime arrived or left; a card that can be
    /// served again was coupled or primed by the holder.
    internal func cardAvailabilityChanged(servable: Bool) {
      if !CardPresence.shared.isReaderCardPresent {
        readerCertificate = nil
      }
      apply(cardReport.availabilityChanged(servable: servable))
      if CardPresence.shared.isReaderCardPresent {
        prepareReaderCard()
      } else {
        Task { await RappReaderSessionHolder.shared.cardLeft() }
      }
    }

    /// Opens the reader card's session and selects the application ahead
    /// of the first request while a requester is connected, and reads the
    /// card's authentication certificate once, so `card.status` can name
    /// the card.
    internal func prepareReaderCard() {
      guard coordinator != nil, CardPresence.shared.isReaderCardPresent else { return }
      let needsCertificate = readerCertificate == nil
      Task {
        await RappReaderSessionHolder.shared.prepare()
        guard needsCertificate else { return }
        let outcome = await RappCardExecutor.readCertificate(
          cardAccessNumber: nil, signatureCertificate: false)
        guard case .result(let certificate) = outcome else { return }
        readerCertificateRead(certificate)
      }
    }

    private func readerCertificateRead(_ certificate: Data) {
      guard CardPresence.shared.isReaderCardPresent else { return }
      readerCertificate = certificate
      reportCardStatus()
    }

    /// Sends the card's word when a transition produced one.
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
        // The custodian's first word on a session is which card can
        // answer (§8.4); the requester offers nothing before it.
        operationsInFlight.removeAll()
        reportedCardStatus = nil
        sessionServing.withLock { $0.idleSince = .now }
        reportCardStatus()
        prepareReaderCard()

      case .inspectPrerequisites(let operationID, _),
        .awaitUserApproval(let operationID, _),
        .executeSafeRead(let operationID, _),
        .executeCardCommand(let operationID, _):
        operationsInFlight.insert(operationID)
        sessionServing.withLock { $0.idleSince = nil }

      case .completed(let operationID, _):
        operationEnded(operationID)
        apply(cardReport.cardAnswered())

      case .terminal(let operationID, let reason):
        operationEnded(operationID)
        // An operation the card did not answer means the card cannot
        // serve only when it is truly gone. A reader card still in its
        // slot is present though one exchange glitched; the near-field
        // card leaves after each tap and keeps the original meaning.
        if reason == .cardError, !CardPresence.shared.isReaderCardPresent {
          apply(cardReport.operationEndedUnattended())
        }

      case .operationEnded(.dropped(let operationID)),
        .operationEnded(.cardExchangeContinues(let operationID)):
        operationEnded(operationID)

      case .closed(let reason):
        operationsInFlight.removeAll()
        sessionServing.withLock { $0 = (nil, nil) }
        endPairingIfOver(reason)
        Task {
          await RappReaderSessionHolder.shared.close()
          await RappNearFieldSessionHolder.shared.closeSession()
        }

      case .progress, .cardStatus:
        break
      }
    }

    internal func operationEnded(_ operationID: RappOperationIdentifier) {
      operationsInFlight.remove(operationID)
      let idle = operationsInFlight.isEmpty
      sessionServing.withLock { $0.idleSince = idle ? .now : nil }
    }

    /// Destroys the pairing the closed session ran over when the session
    /// ended it: the requester revoked it, or this phone delivered the close
    /// of a pairing its holder forgot (RAPP v26.10.21 §4.6 items 2 to 4).
    private func endPairingIfOver(_ reason: RappConnectionCoordinator.CloseReason) {
      guard reason.peerRevokedPairing || reason == .handshake(.revocationNoticeDelivered),
        let pairID = activePairID
      else { return }
      try? RappPairRevocation.revoke(pairID: pairID, in: vault, clock: RappPlatformClock())
      RappPairNames.forget(pairID: pairID)
      activePairID = nil
      NotificationCenter.default.post(
        name: RappPairingModel.pairingsDidChangeNotification, object: nil)
    }
  }
#endif
