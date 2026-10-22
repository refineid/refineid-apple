// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if (os(macOS) || os(iOS)) && REFINEID_STREAM_TRANSPORT
  import CardCore
  import Foundation
  import RappEngine

  /// The standing session with the phone whose word the offered identity
  /// rests on (RAPP v26.10.22 §8.3, §8.4).
  extension PersistentTokenRegistry {
    /// Seconds between dials while the phone is on the network and no
    /// session is open.
    private static let redialDelaySeconds = 2

    /// How long the redial loop may run without a usable session.
    ///
    /// Past this it stops and leaves a terminal state (R-58). It sits above
    /// the longest interactive operation, so a legitimate long operation
    /// during which the phone refuses a second session is not mistaken for
    /// a dead loop. A fresh advertisement or a user action restarts it. The
    /// offered identity follows ``RemoteIdentityOffer`` alone.
    private static let abortLoopSeconds = 150

    private static var redialDelay: Duration { .seconds(redialDelaySeconds) }

    /// The pairing a session runs over.
    ///
    /// It is the one whose hint the phone in sight carries, which for a
    /// pairing this computer forgot delivers its `pairing_revoked` close to
    /// that phone and no other (RAPP v26.10.22 §4.6 item 2); with none in
    /// sight, the chosen usable pairing, else the newest. A forgotten pairing
    /// is dialed only when its phone is in sight, and not once its 30 days
    /// ran out (§4.6 item 3).
    private static func sessionPair(in vault: RappDeviceVault, inSight: Data?) -> RappPairRecord? {
      RappPairRevocation.expireRevocationNotices(in: vault, clock: RappPlatformClock())
      let pairIDs = (try? vault.activePairIDs()) ?? []
      let pairs = pairIDs.compactMap { try? RappPairRecord.loadFromVault(pairId: $0, vault: vault) }
      if let inSight, let named = pairs.first(where: { $0.metadata().pairId == inSight }) {
        return named
      }
      let usable = pairs.filter { $0.metadata().forgottenAtMs == nil }
      if let selected = try? vault.selectedPairID(),
        let chosen = usable.first(where: { $0.metadata().pairId == selected })
      {
        return chosen
      }
      guard let newest = usable.max(by: { $0.metadata().createdAtMs < $1.metadata().createdAtMs })
      else { return nil }
      try? vault.selectPair(pairID: newest.metadata().pairId)
      return newest
    }

    /// Dials the phone the browser reports, unless a session is open.
    internal func openHolderSession() {
      guard Self.isRemoteCardEnabled, !CardPresence.shared.isReaderCardPresent,
        holderIsAdvertising, holderSession == nil
      else { return }
      let vault = RappDeviceVault()
      guard let pair = Self.sessionPair(in: vault, inSight: pairInSight) else {
        Self.withdrawPublishedIdentity()
        return
      }
      let token = UUID()
      let session = RappHeldRequesterSession(pair: pair) { report in
        Task { @MainActor in
          Self.shared.holderSessionReported(report, token: token)
        }
      }
      holderSession = session
      holderSessionToken = token
      holderReportsNoCard = false
      session.start()
    }

    /// Ends the open session, if any, and forgets what it said; an offered
    /// identity then follows the grace (§8.4 item 3).
    internal func closeHolderSession() {
      redialTask?.cancel()
      redialTask = nil
      holderCardStatus = .absent
      holderReportsNoCard = false
      holderSession?.close()
      holderSession = nil
      holderSessionToken = nil
      confirmationLost()
    }

    /// Ends the open session with `pairing_revoked` when it runs over
    /// `pairID`, as the pairing is forgotten (RAPP v26.10.22 §4.6 item 1);
    /// false when no session over `pairID` is open or the close did not
    /// leave, so the pairing is kept forgotten for its next session.
    internal func closeSessionForRevocation(pairID: Data) async -> Bool {
      guard let session = holderSession, session.pairID == pairID else { return false }
      redialTask?.cancel()
      redialTask = nil
      holderCardStatus = .absent
      holderReportsNoCard = false
      holderSession = nil
      holderSessionToken = nil
      let told = await session.closePairingRevoked()
      Self.withdrawPublishedIdentity()
      return told
    }

    private func holderSessionReported(_ report: RappHeldRequesterSession.Report, token: UUID) {
      guard token == holderSessionToken else { return }
      switch report {
      case .established:
        break

      case .cardStatus(let status):
        // Any card status means the session established and reached the
        // custodian's first word (RAPP §8.4): the redial loop succeeded,
        // so its deadline starts over for any later loss (R-58).
        continuousFailureSince = nil
        holderCardStatus = status
        if case .absent = status {
          holderReportsNoCard = true
        } else {
          holderReportsNoCard = false
        }
        let offered = (certificateDER ?? Self.publishedCertificateDER())
          .flatMap(RappCertificateFingerprint.init(certificate:))
        respond(to: identityOffer.receive(status, offered: offered, at: .now))

      case .closed(let reason):
        holderSessionEnded(reason)
      }
    }

    /// Acts on what the phone's `card.status` did to the offer: the card
    /// offered is published again, another card's identity is withdrawn at
    /// once and the certificate read afresh, and absence leaves the offer
    /// to its grace (RAPP v26.10.22 §8.4 items 2 and 3).
    private func respond(to response: RemoteIdentityOffer.Response) {
      switch response {
      case .absent:
        armOfferLapse()

      case .differentCard:
        Self.withdrawPublishedIdentity()
        guard confirmationRegained() else { return }
        readCertificate()

      case .nothingOffered:
        guard confirmationRegained() else { return }
        readCertificate()

      case .offeredCard:
        guard confirmationRegained() else { return }
        ensurePublished()
      }
    }

    /// A session confirmed a card: the offer's lapse is called off; false
    /// while a reader card here takes priority over the phone's.
    private func confirmationRegained() -> Bool {
      offerLapseTask?.cancel()
      offerLapseTask = nil
      return !CardPresence.shared.isReaderCardPresent
    }

    /// Reads the certificate over the open session.
    private func readCertificate() {
      guard let session = holderSession, !isRunning else { return }
      guard fetchBackoff.permits(at: .now) else {
        retryReadAfterFailure()
        return
      }
      beginRead()
      Task {
        let fetched: Data?
        do {
          fetched = try await session.readAuthenticationCertificate()
        } catch {
          fetched = nil
          #if DEBUG
            DevErrorLog.report(
              "certificate read failed: \(DevErrorLog.reason(error))", source: .app)
          #endif
        }
        finishRead(fetched)
      }
    }

    /// Reads again after the backoff, while the phone still says present.
    internal func retryReadAfterFailure() {
      let delay = CertificateFetchBackoff.delay(afterFailures: fetchBackoff.failures)
      Task { @MainActor in
        try? await Task.sleep(for: delay)
        guard case .present = holderCardStatus, certificateDER == nil else { return }
        readCertificate()
      }
    }

    private func holderSessionEnded(_ reason: RappConnectionCoordinator.CloseReason) {
      #if DEBUG
        if let failure = reason.devErrorName(midOperation: isRunning) {
          DevErrorLog.report("phone session closed: \(failure)", source: .app)
        }
      #endif
      let ended = holderSession
      holderSession = nil
      holderSessionToken = nil
      holderCardStatus = .absent
      holderReportsNoCard = false
      if reason.peerRevokedPairing {
        if let ended {
          holderRevoked(pairID: ended.pairID)
        }
        return
      }
      if reason == .handshake(.revocationNoticeDelivered) {
        if let ended {
          revocationNoticeDelivered(pairID: ended.pairID)
        }
        return
      }
      if reason.serviceWithdrawn {
        // The phone announced it stopped serving: a verified withdrawal
        // takes the identity at once; its next session record brings it
        // back (§4.5 item 6).
        Self.withdrawPublishedIdentity()
        return
      }
      confirmationLost()
      guard !CardPresence.shared.isReaderCardPresent else {
        Self.withdrawPublishedIdentity()
        return
      }
      if holderIsAdvertising {
        scheduleRedial()
      }
    }

    /// No open session confirms the card any more: the offer lapses after
    /// the grace unless a session reports the card present again (§8.4
    /// item 3).
    private func confirmationLost() {
      identityOffer.loseConfirmation(at: .now)
      armOfferLapse()
    }

    /// Withdraws the identity once the offer has lapsed.
    private func armOfferLapse() {
      guard offerLapseTask == nil, let lapsesAt = identityOffer.lapsesAt else { return }
      offerLapseTask = Task { @MainActor in
        try? await Task.sleep(until: lapsesAt, clock: .continuous)
        guard !Task.isCancelled else { return }
        offerLapseTask = nil
        guard identityOffer.hasLapsed(at: .now) else { return }
        Self.withdrawPublishedIdentity()
      }
    }

    /// Dials again after ``redialDelay``, until the loop has run for
    /// ``abortLoopSeconds`` without ever reaching a usable session.
    private func scheduleRedial() {
      redialTask?.cancel()
      let now = ContinuousClock.now
      let since = continuousFailureSince ?? now
      continuousFailureSince = since
      guard now - since < .seconds(Self.abortLoopSeconds) else {
        // The loop has not produced a usable session within the deadline.
        // Stop dialing and leave a terminal state instead of looping; a
        // fresh advertisement (holderIsAdvertising) or a user action
        // starts a new attempt. The offer's grace has run by now.
        #if DEBUG
          DevErrorLog.report(
            "phone session: no usable session in \(Self.abortLoopSeconds) s, stopped dialling",
            source: .app)
        #endif
        continuousFailureSince = nil
        redialTask = nil
        return
      }
      redialTask = Task { @MainActor in
        try? await Task.sleep(for: Self.redialDelay)
        guard !Task.isCancelled else { return }
        redialTask = nil
        openHolderSession()
      }
    }
  }
#endif
