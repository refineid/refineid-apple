// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS) || os(iOS)
  import CardCore
  import Foundation
  import RappEngine

  /// The standing session with the phone whose word the offered identity
  /// rests on (RAPP v26.11.8 §8.3, §8.4), over the stream while Bonjour
  /// shows the phone and over Bluetooth otherwise (RAPP transport
  /// hierarchy §3).
  extension PersistentTokenRegistry {
    /// How long one Bluetooth dial scans for the phone before it starts
    /// over.
    private static let bluetoothScanSeconds: TimeInterval = 30

    /// How long after a start the first dial waits for Bonjour to show the
    /// phone, so the stream is preferred when both could reach it.
    private static let settleSeconds = 3

    /// The policy of a dial over Bluetooth: the interactive one, scanning
    /// for its own window.
    internal static var bluetoothPolicy: RappRequesterPolicy {
      RappRequesterPolicy(
        maximumOperationLifetimeMilliseconds:
          RappRequesterPolicy.interactive.maximumOperationLifetimeMilliseconds,
        synchronousWaitTimeout: RappRequesterPolicy.interactive.synchronousWaitTimeout,
        discoveryTimeout: bluetoothScanSeconds)
    }

    /// What decides the next dial's transport now, and whether remote use
    /// being off or a card in this computer's reader leaves nothing to dial.
    internal var transportPolicy: RequesterTransportPolicy {
      RequesterTransportPolicy(
        remoteUseOn: Self.remoteUseOn,
        localCardPresent: CardPresence.shared.isReaderCardPresent,
        streamInSight: holderIsAdvertising && holderRecordListed,
        streamFailedInSight: streamFailedInSight,
        bluetoothUsable: bluetoothUsable)
    }

    /// The pairing a session runs over.
    ///
    /// It is the usable one whose hint the phone in sight carries; with none
    /// in sight, the chosen usable pairing, else the newest. A forgotten
    /// pairing is never the session's: the revocation backlog delivers its
    /// close on a session of its own (RAPP v26.11.8 §4.6 item 6).
    private static func sessionPair(in vault: RappDeviceVault, inSight: Data?) -> RappPairRecord? {
      let pairIDs = (try? vault.activePairIDs()) ?? []
      let usable = pairIDs.compactMap { pairID in
        try? RappPairRecord.loadFromVault(pairId: pairID, vault: vault)
      }
      .filter { $0.metadata().forgottenAtMs == nil }
      if let inSight, let named = usable.first(where: { $0.metadata().pairId == inSight }) {
        return named
      }
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

    /// Dials the phone along the transport the policy picks, unless a
    /// session is being dialled or open on any transport, remote use is off,
    /// or a card in this computer's reader overrides the phone; while the
    /// wait after the last session runs, the dial is put off until it is
    /// over.
    internal func openHolderSession() {
      guard Self.dialsPhones, holderSession == nil, let transport = transportPolicy.nextDial
      else { return }
      // A forgotten pairing's close holds the Bluetooth link; the dial
      // follows it.
      if transport == .bluetooth, revokingOverBluetooth { return }
      guard sessionSlot.mayDial(at: .now) else {
        if redialTask == nil { scheduleRedial() }
        return
      }
      let vault = RappDeviceVault()
      guard let pair = Self.sessionPair(in: vault, inSight: pairInSight) else {
        Self.withdrawPublishedIdentity()
        return
      }
      let route: RappHeldRequesterSession.Route
      let policy: RappRequesterPolicy
      switch transport {
      case .stream:
        route = .stream
        policy = .interactive

      case .bluetooth:
        route = .bluetooth(bluetoothPeers.dialing(at: .now))
        policy = Self.bluetoothPolicy
      }
      let token = UUID()
      let session = RappHeldRequesterSession(pair: pair, route: route, policy: policy) { report in
        Task { @MainActor in
          Self.shared.holderSessionReported(report, token: token)
        }
      }
      guard sessionSlot.dial(over: transport, at: .now) else { return }
      settleDialTask?.cancel()
      settleDialTask = nil
      holderSession = session
      holderSessionToken = token
      holderCardStatus = nil
      #if DEBUG
        print("[persistent-token] dialing the phone over \(transport)")
        fflush(stdout)
      #endif
      session.start()
    }

    /// Dials once Bonjour has had its chance to show the phone, so a start
    /// with the phone on the network takes the stream.
    internal func dialAfterSettling() {
      settleDialTask?.cancel()
      settleDialTask = Task { @MainActor in
        try? await Task.sleep(for: .seconds(Self.settleSeconds))
        guard !Task.isCancelled else { return }
        settleDialTask = nil
        openHolderSession()
      }
    }

    /// Ends the open session, if any, and forgets what it said; an offered
    /// identity then follows the grace (§8.4 item 3).
    internal func closeHolderSession() {
      redialTask?.cancel()
      redialTask = nil
      settleDialTask?.cancel()
      settleDialTask = nil
      holderCardStatus = nil
      holderSession?.close()
      forgetHeldSession()
      confirmationLost()
    }

    /// Clears what the registry knows of the session it let go; a session
    /// that was established is recorded in its pairing as it ends (RAPP
    /// v26.11.8 §4.6 item 5).
    internal func forgetHeldSession() {
      if sessionSlot.isEstablished, let pairID = holderSession?.pairID {
        Self.recordSession(pairID: pairID)
      }
      holderSession = nil
      holderSessionToken = nil
      sessionSlot.released()
      holderOverBluetooth = false
    }

    private func holderSessionReported(_ report: RappHeldRequesterSession.Report, token: UUID) {
      guard token == holderSessionToken else { return }
      switch report {
      case .established:
        holderEstablished()

      case .cardStatus(let status):
        cardStatusReported(status)

      case .peerNamed(let name):
        if let pairID = holderSession?.pairID {
          RappPeerName.record(name, pairID: pairID, in: RappDeviceVault())
        }

      case .bluetoothPeer(let peer, let routed):
        bluetoothPeerReported(peer, routed: routed)

      case .bluetoothTrace(let step):
        bluetoothStep(step)

      case .closed(let reason):
        holderSessionEnded(reason)

      case .localNetworkDenied:
        #if DEBUG
          DevErrorLog.report("phone session: the local network is denied", source: .app)
        #endif
        localNetworkDenied = true
      }
    }

    /// The session with the phone is up.
    private func holderEstablished() {
      localNetworkDenied = false
      sessionSlot.established()
      if let pairID = holderSession?.pairID {
        Self.recordSession(pairID: pairID)
      }
      holderOverBluetooth = sessionSlot.transport == .bluetooth
      if sessionSlot.transport == .stream {
        streamFailedInSight = false
      }
    }

    /// Notes whether the Bluetooth advertiser `peer` routed the session.
    private func bluetoothPeerReported(_ peer: UUID, routed: Bool) {
      if routed {
        bluetoothPeers.routed(peer)
      } else {
        bluetoothPeers.refused(peer, at: .now)
      }
    }

    /// Takes the phone's word on its card and its card reader.
    ///
    /// Any card status means the session established and reached the
    /// custodian's first word (RAPP §8.4): the redial loop succeeded, so
    /// its deadline starts over for any later loss (R-58). The reader
    /// changes only how the card is asked for; the card alone governs the
    /// offer (§8.4 items 3 and 6, CC-82).
    private func cardStatusReported(_ status: RappCardStatus) {
      if case .absent = status.card {
        connectedAfterPairing()
      }
      continuousFailureSince = nil
      holderCardStatus = status
      let offered = (certificateDER ?? Self.publishedCertificateDER())
        .flatMap(RappCertificateFingerprint.init(certificate:))
      respond(to: identityOffer.receive(status.card, offered: offered, at: .now))
    }

    /// Acts on what the phone's `card.status` did to the offer: the card
    /// offered is published again, another card's identity is withdrawn at
    /// once and the certificate read afresh, and absence leaves the offer
    /// to its grace (RAPP v26.11.8 §8.4 items 2 and 3).
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
        guard case .present? = holderCardStatus?.card, certificateDER == nil else { return }
        readCertificate()
      }
    }

    private func holderSessionEnded(_ reason: RappConnectionCoordinator.CloseReason) {
      #if DEBUG
        reportEnd(reason)
      #endif
      let ended = holderSession
      // The peripheral the session held is free for the closes it held
      // back (RAPP v26.11.8 §4.6 item 6).
      let freed = holderOverBluetooth ? bluetoothPeers.preferred : nil
      if sessionSlot.transport == .stream, !sessionSlot.isEstablished, holderIsAdvertising {
        // The record is there and the phone did not answer: a suspended
        // app leaves its record behind, so the next dial tries Bluetooth
        // (CC-72).
        streamFailedInSight = true
      }
      forgetHeldSession()
      holderCardStatus = nil
      if let freed {
        bluetoothPeripheralAppeared(freed, in: RappDeviceVault())
      }
      let end = PhoneSessionEnd(reason)
      guard !concluded(by: end, pairID: ended?.pairID) else { return }
      sessionSlot.ended(at: .now)
      confirmationLost()
      guard !CardPresence.shared.isReaderCardPresent else {
        Self.withdrawPublishedIdentity()
        return
      }
      if transportPolicy.nextDial != nil {
        scheduleRedial()
      }
    }

    /// Acts on an end that is not a loss and answers true; a loss is left
    /// to the redial that follows it (RAPP v26.11.8 §4.5 item 6).
    private func concluded(by end: PhoneSessionEnd, pairID: Data?) -> Bool {
      switch end {
      case .pairingRevoked:
        if let pairID { holderRevoked(pairID: pairID, in: RappDeviceVault()) }

      case .revocationNoticeDelivered:
        if let pairID { revocationNoticeDelivered(pairID: pairID) }

      case .withdrawn:
        // The phone's statement, not a fault: no back-off is recorded, and
        // the next dial follows the phone's announcement.
        holderWithdrew()

      case .violation:
        holderViolated()

      case .lost:
        return false
      }
      return true
    }

    /// The session ended for an authenticated protocol violation.
    ///
    /// The pairing stays and the identity follows its grace; the next dial
    /// waits for the phone to appear again or a consumer to ask (RAPP
    /// v26.11.8 §4.5 item 6). A version mismatch is the likely cause.
    private func holderViolated() {
      holderIsAdvertising = false
      confirmationLost()
    }

    #if DEBUG
      /// Names a session that ended as a failure on the development error
      /// strip; a Bluetooth dial that reached no phone within its scan is
      /// the discovery failure itself.
      private func reportEnd(_ reason: RappConnectionCoordinator.CloseReason) {
        let peer = DevErrorLog.peerName(pairID: holderSession?.pairID, vault: RappDeviceVault())
        if sessionSlot.transport == .bluetooth, !sessionSlot.isEstablished,
          reason == .transportFailure
        {
          DevErrorLog.report(
            "phone over Bluetooth: not reached within the scan, \(peer)", source: .app)
        } else if let failure = reason.devErrorName(midOperation: isRunning) {
          let route = sessionSlot.transport == .bluetooth ? "Bluetooth" : "network"
          DevErrorLog.report("phone session closed: \(failure), \(peer), \(route)", source: .app)
        }
      }
    #endif

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

  }
#endif
