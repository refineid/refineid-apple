// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if (os(macOS) || os(iOS)) && REFINEID_STREAM_TRANSPORT
  import CardCore
  import Foundation
  import RappEngine

  /// The standing session with the phone that the offered identity rests
  /// on (RAPP v26.10.21 §8.3, §8.4).
  extension PersistentTokenRegistry {
    /// Seconds a session may stay down, while the phone stays on the
    /// network, before the identity is withdrawn.
    ///
    /// The phone yields an idle session to the token extension's own
    /// dial, and that operation may run its whole lifetime before the
    /// app can dial again; an identity withdrawn under a signature in
    /// progress would end the signature.
    private static let sessionLossGraceSeconds = 130

    /// Seconds between dials while the phone is on the network and no
    /// session is open.
    private static let redialDelaySeconds = 2

    /// How long the redial loop may run without a usable session.
    ///
    /// Past this it stops and leaves a terminal state (R-58). It sits
    /// above the loss grace (``sessionLossGraceSeconds``) and the longest
    /// interactive operation, so a legitimate long operation during which
    /// the phone refuses a second session is not mistaken for a dead
    /// loop. A fresh advertisement or a user action restarts it.
    private static let abortLoopSeconds = 150

    private static var sessionLossGrace: Duration { .seconds(sessionLossGraceSeconds) }

    private static var redialDelay: Duration { .seconds(redialDelaySeconds) }

    /// The pairing a session runs over.
    ///
    /// It is the one whose hint the phone in sight carries, which for a
    /// pairing this computer forgot delivers its `pairing_revoked` close to
    /// that phone and no other (RAPP v26.10.21 §4.6 item 2); with none in
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
      let session = RappHeldRequesterSession(pair: pair) { report in
        Task { @MainActor in
          Self.shared.holderSessionReported(report)
        }
      }
      holderSession = session
      session.start()
    }

    /// Ends the open session, if any, and forgets what it said.
    internal func closeHolderSession() {
      redialTask?.cancel()
      redialTask = nil
      sessionLossTask?.cancel()
      sessionLossTask = nil
      holderCardStatus = .absent
      holderSession?.close()
      holderSession = nil
    }

    /// Ends the open session with `pairing_revoked` when it runs over
    /// `pairID`, as the pairing is forgotten (RAPP v26.10.21 §4.6 item 1);
    /// false when no session over `pairID` is open or the close did not
    /// leave, so the pairing is kept forgotten for its next session.
    internal func closeSessionForRevocation(pairID: Data) async -> Bool {
      guard let session = holderSession, session.pairID == pairID else { return false }
      redialTask?.cancel()
      redialTask = nil
      sessionLossTask?.cancel()
      sessionLossTask = nil
      holderCardStatus = .absent
      holderSession = nil
      let told = await session.closePairingRevoked()
      Self.withdrawPublishedIdentity()
      return told
    }

    private func holderSessionReported(_ report: RappHeldRequesterSession.Report) {
      switch report {
      case .established:
        break

      case .cardStatus(let status):
        // Any card status means the session established and reached the
        // custodian's first word (RAPP §8.4): the redial loop succeeded,
        // so its deadline starts over for any later loss (R-58).
        continuousFailureSince = nil
        holderCardStatus = status
        switch status {
        case .present:
          sessionLossTask?.cancel()
          sessionLossTask = nil
          offerIdentity()

        case .absent:
          Self.withdrawPublishedIdentity()
        }

      case .closed(let reason):
        holderSessionEnded(reason)
      }
    }

    /// Offers the identity of the card the phone names: a certificate
    /// already held is published again only while its fingerprint is the
    /// one the phone reported on this session, any other is read afresh
    /// (RAPP v26.10.21 §8.4 item 2).
    private func offerIdentity() {
      guard case .present(let fingerprint) = holderCardStatus,
        !CardPresence.shared.isReaderCardPresent
      else { return }
      let held = certificateDER ?? Self.publishedCertificateDER()
      if let held, RappCertificateFingerprint(certificate: held) == fingerprint {
        ensurePublished()
        return
      }
      if held != nil {
        Self.withdrawPublishedIdentity()
      }
      readCertificate()
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
        let fetched = try? await session.readAuthenticationCertificate()
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
      let ended = holderSession
      holderSession = nil
      holderCardStatus = .absent
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
      switch reason {
      case _ where reason.serviceWithdrawn:
        // The phone stopped serving; its next session record brings it
        // back.
        Self.withdrawPublishedIdentity()

      case .localRequest:
        break

      case .handshake, .transportFailure, .operation:
        guard holderIsAdvertising, !CardPresence.shared.isReaderCardPresent else {
          Self.withdrawPublishedIdentity()
          return
        }
        armSessionLossGrace()
        scheduleRedial()
      }
    }

    /// Withdraws the identity unless a session says present again within
    /// ``sessionLossGrace``.
    private func armSessionLossGrace() {
      guard sessionLossTask == nil, certificateDER != nil else { return }
      sessionLossTask = Task { @MainActor in
        try? await Task.sleep(for: Self.sessionLossGrace)
        guard !Task.isCancelled else { return }
        sessionLossTask = nil
        guard case .absent = holderCardStatus else { return }
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
        // starts a new attempt.
        continuousFailureSince = nil
        redialTask = nil
        Self.withdrawPublishedIdentity()
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
