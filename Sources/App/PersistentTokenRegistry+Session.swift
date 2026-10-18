// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if (os(macOS) || os(iOS)) && REFINEID_STREAM_TRANSPORT
  import CardCore
  import Foundation
  import RappEngine

  /// The standing session with the phone that the offered identity rests
  /// on (RAPP v26.10.18 §8.4).
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

    private static var sessionLossGrace: Duration { .seconds(sessionLossGraceSeconds) }

    private static var redialDelay: Duration { .seconds(redialDelaySeconds) }

    /// The pairing a session runs over: the chosen one, else the newest.
    private static func sessionPair(in vault: RappDeviceVault) -> RappPairRecord? {
      let pairIDs = (try? vault.activePairIDs()) ?? []
      guard !pairIDs.isEmpty else { return nil }
      if let selected = try? vault.selectedPairID(), pairIDs.contains(selected) {
        return try? RappPairRecord.loadFromVault(pairId: selected, vault: vault)
      }
      let pairs = pairIDs.compactMap { try? RappPairRecord.loadFromVault(pairId: $0, vault: vault) }
      guard let newest = pairs.max(by: { $0.metadata().createdAtMs < $1.metadata().createdAtMs })
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
      guard let pair = Self.sessionPair(in: vault) else {
        Self.withdrawPublishedIdentity()
        return
      }
      let session = RappHeldRequesterSession(pair: pair, vault: vault) { report in
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
      holderCardPresent = false
      holderSession?.close()
      holderSession = nil
    }

    /// Ends the open session with `pairing_revoked` when it runs over
    /// `pairID`, before the pairing is forgotten (RAPP v26.10.18 §4.6).
    internal func closeSessionForRevocation(pairID: Data) async {
      guard let session = holderSession, session.pairID == pairID else { return }
      redialTask?.cancel()
      redialTask = nil
      sessionLossTask?.cancel()
      sessionLossTask = nil
      holderCardPresent = false
      holderSession = nil
      await session.closePairingRevoked()
      Self.withdrawPublishedIdentity()
    }

    private func holderSessionReported(_ report: RappHeldRequesterSession.Report) {
      switch report {
      case .established:
        break

      case .cardStatus(let present):
        holderCardPresent = present
        if present {
          sessionLossTask?.cancel()
          sessionLossTask = nil
          offerIdentity()
        } else {
          Self.withdrawPublishedIdentity()
        }

      case .closed(let reason):
        holderSessionEnded(reason)
      }
    }

    /// Offers the identity the phone's present card backs: a certificate
    /// already held is published again, one not yet held is read.
    private func offerIdentity() {
      guard holderCardPresent, !CardPresence.shared.isReaderCardPresent else { return }
      if certificateDER != nil {
        ensurePublished()
        return
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
        guard holderCardPresent, certificateDER == nil else { return }
        readCertificate()
      }
    }

    private func holderSessionEnded(_ reason: RappConnectionCoordinator.CloseReason) {
      let ended = holderSession
      holderSession = nil
      holderCardPresent = false
      switch reason {
      case .operation(.serviceWithdrawn):
        // The phone stopped serving; its next session record brings it
        // back.
        Self.withdrawPublishedIdentity()

      case .operation(.pairRevoked):
        if let ended {
          holderRevoked(pairID: ended.pairID)
        }

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
        guard !holderCardPresent else { return }
        Self.withdrawPublishedIdentity()
      }
    }

    /// Dials again after ``redialDelay``.
    private func scheduleRedial() {
      redialTask?.cancel()
      redialTask = Task { @MainActor in
        try? await Task.sleep(for: Self.redialDelay)
        guard !Task.isCancelled else { return }
        redialTask = nil
        openHolderSession()
      }
    }
  }
#endif
