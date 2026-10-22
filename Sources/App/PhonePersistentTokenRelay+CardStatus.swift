// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(iOS) && REFINEID_LOCAL_CARD
  import CardCore
  import Foundation
  import RappEngine

  /// The custodian's word on its card (RAPP v26.10.22 §8.4).
  @MainActor
  extension PhonePersistentTokenRelay {
    /// What this phone knows of the reader card it serves.
    internal struct ReaderCard {
      /// The card's authentication certificate, once read; nil while no
      /// reader card is present.
      internal var certificate: Data?
      /// The preparation and certificate read under way, so a second
      /// request waits for it instead of queueing another read.
      internal var preparation: Task<Void, Never>?
      /// Changes whenever the reader card arrives or leaves, so a
      /// certificate read from an earlier card is never taken for the
      /// current one.
      internal var epoch = UUID()
    }

    /// The authentication certificate of the card this phone serves: the
    /// reader card's once read, else the primed near-field card's.
    private var servedCertificate: Data? {
      if CardPresence.shared.isReaderCardPresent {
        return readerCard.certificate
      }
      return PrimeStore.storedIdentities().first?.certDER
    }

    /// The card the phone holds now, by the fingerprint of its
    /// authentication certificate; nil while it holds none, or one whose
    /// certificate it has not read yet.
    internal var servedCardFingerprint: RappCertificateFingerprint? {
      guard Self.canServeCard else { return nil }
      return servedCertificate.flatMap(RappCertificateFingerprint.init(certificate:))
    }

    /// Which card the phone holds (§8.4 items 1 and 2).
    ///
    /// Present while it holds one whose authentication certificate is known,
    /// so the requester can tell which card it is. An operation the card did
    /// not answer changes nothing here.
    internal var cardStatus: RappCardStatus {
      guard let fingerprint = servedCardFingerprint else { return .absent }
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

    /// A reader card or a prime arrived or left: the requester hears which
    /// card the phone holds now, and a PIN 1 held for another card ends
    /// (§11 item 2).
    internal func cardAvailabilityChanged() {
      readerCard.epoch = UUID()
      if !CardPresence.shared.isReaderCardPresent {
        readerCard.certificate = nil
      }
      HeldPin1.shared.keep(onlyFor: servedCardFingerprint)
      reportCardStatus()
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
    ///
    /// Both run on the reader holder's chain, the card turn the operations
    /// take (RAPP v26.10.22 §8.2 item 2); one preparation runs at a time,
    /// and a card that changed meanwhile is prepared once it is done.
    internal func prepareReaderCard() {
      guard coordinator != nil, CardPresence.shared.isReaderCardPresent,
        readerCard.preparation == nil
      else { return }
      let epoch = readerCard.epoch
      readerCard.preparation = Task {
        await RappReaderSessionHolder.shared.prepare()
        if readerCard.certificate == nil {
          let outcome = await RappCardExecutor.readCertificate(
            cardAccessNumber: nil, signatureCertificate: false)
          if case .result(let certificate) = outcome {
            readerCertificateRead(certificate, epoch: epoch)
          }
        }
        readerCard.preparation = nil
        if epoch != readerCard.epoch {
          prepareReaderCard()
        }
      }
    }

    /// Takes the certificate read from the reader card present since
    /// `epoch`; one read from an earlier card is dropped.
    private func readerCertificateRead(_ certificate: Data, epoch: UUID) {
      guard epoch == readerCard.epoch, CardPresence.shared.isReaderCardPresent else { return }
      readerCard.certificate = certificate
      reportCardStatus()
    }

    internal func observe(
      _ event: RappConnectionCoordinator.Event,
      connectionID: UUID
    ) {
      #if DEBUG
        // Ahead of the connection check: a session whose transport has
        // already gone reports its close after the connection was dropped.
        if case .closed(let reason) = event,
          let failure = reason.devErrorName(midOperation: !operationsInFlight.isEmpty)
        {
          DevErrorLog.report("session closed: \(failure)", source: .app)
        }
      #endif
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

      case .completed(let operationID, _), .terminal(let operationID, _),
        .operationEnded(.dropped(let operationID)),
        .operationEnded(.cardExchangeContinues(let operationID)),
        .answered(let operationID):
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
    /// of a pairing its holder forgot (RAPP v26.10.22 §4.6 items 2 to 4).
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
