// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS) || os(iOS)
  import CardCore
  import Foundation
  import RappEngine

  /// The requester's revocation backlog (RAPP v26.11.8 §4.6 item 6, STPA
  /// CC-118).
  ///
  /// A pairing its user forgot, by turning remote use off or by pairing
  /// another phone, is stored forgotten: it serves nothing and keeps its key
  /// only for the `pairing_revoked` close. While any waits, this computer
  /// browses for the hints of those pairings, whatever remote use and the
  /// local reader are, and scans for RAPP peripherals over Bluetooth. Each
  /// time a phone appears for one, by its session record or as a peripheral
  /// newly in sight, it opens one session by the route that appeared, which
  /// sends the close first and waits for the echo; that appearance tries no
  /// other route. The echo
  /// destroys the pairing. Nothing is dialed on a timer, and a pairing whose
  /// phone does not come back goes at its idle expiry, 30 days after its last
  /// session. Several forgotten pairings may wait at once.
  extension PersistentTokenRegistry {
    /// One forgotten pairing the backlog follows.
    private struct ForgottenPairing: Sendable {
      let key: String
      let pairID: Data
      let record: RappPairRecord
    }

    /// Whether the backlog browses the network: not in a process that only
    /// hosts the unit tests, which keep the backlog's model and reach no
    /// phone and no local-network permission.
    private static let backlogBrowses =
      ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil

    /// The forgotten pairings in `vault`, once the ones whose idle expiry
    /// passed are destroyed (§4.6 item 3).
    private static func forgottenPairings(in vault: RappDeviceVault) -> [ForgottenPairing] {
      RappPairRevocation.expireRevocationNotices(in: vault, clock: RappPlatformClock())
      let pairIDs = (try? vault.activePairIDs()) ?? []
      return pairIDs.compactMap { pairID -> ForgottenPairing? in
        guard let pair = try? RappPairRecord.loadFromVault(pairId: pairID, vault: vault),
          pair.metadata().forgottenAtMs != nil
        else { return nil }
        return ForgottenPairing(key: pairingKey(pairID), pairID: pairID, record: pair)
      }
    }

    /// The classifier the browser calls on its own queue: the forgotten
    /// pairing whose discovery hint a session record carries.
    nonisolated private static func backlogClassifier(
      among pairings: [ForgottenPairing]
    ) -> @Sendable ([String: String], String) -> String? {
      { record, _ in
        let now = Date()
        return pairings.first { pairing in
          StreamRendezvousName.sessionRecord(record, holds: pairing.record, at: now)
        }?.key
      }
    }

    /// The appearance handler the browser calls on its own queue; it hops
    /// to the main actor.
    nonisolated private static func backlogAppearanceHandler(
      pairIDs: [String: Data], in vault: RappDeviceVault
    ) -> @Sendable (String) -> Void {
      { key in
        guard let pairID = pairIDs[key] else { return }
        Task { @MainActor in
          Self.shared.forgottenPairingAppeared(pairID, in: vault)
        }
      }
    }

    /// The Bluetooth appearance handler the watcher calls on its own queue;
    /// it hops to the main actor.
    nonisolated private static func bluetoothAppearanceHandler(
      in vault: RappDeviceVault
    ) -> @Sendable (UUID) -> Void {
      { peripheral in
        Task { @MainActor in
          Self.shared.bluetoothPeripheralAppeared(peripheral, in: vault)
        }
      }
    }

    /// Follows the backlog as the device's vault holds it now.
    internal func followRevocationBacklog() {
      followRevocationBacklog(in: RappDeviceVault())
    }

    /// Follows the backlog as `vault` holds it now: browses while a
    /// forgotten pairing waits and stops once none does.
    internal func followRevocationBacklog(in vault: RappDeviceVault) {
      guard Self.dialsPhones else { return }
      let pairings = Self.forgottenPairings(in: vault)
      guard !pairings.isEmpty else {
        revocationBacklog?.cancel()
        revocationBacklog = nil
        revocationBluetoothWatch?.cancel()
        revocationBluetoothWatch = nil
        return
      }
      if Self.dialsOverBluetooth, revocationBluetoothWatch == nil {
        let watch = RappBleAppearanceWatcher(
          onAppeared: Self.bluetoothAppearanceHandler(in: vault))
        revocationBluetoothWatch = watch
        if Self.backlogBrowses {
          watch.start()
        }
      }
      let keys = Set(pairings.map(\.key))
      let classify = Self.backlogClassifier(among: pairings)
      let appeared = Self.backlogAppearanceHandler(
        pairIDs: Dictionary(uniqueKeysWithValues: pairings.map { ($0.key, $0.pairID) }),
        in: vault)
      if let browser = revocationBacklog {
        // A phone that stays in sight is not a new appearance because
        // another pairing joined or left the backlog.
        if browser.following != keys {
          browser.update(following: keys, classifyingRecord: classify, onAppeared: appeared)
        }
        return
      }
      let browser = RappRevocationBacklogBrowser(
        following: keys, classifyingRecord: classify, onAppeared: appeared)
      revocationBacklog = browser
      if Self.backlogBrowses {
        browser.start()
      }
    }

    /// The phone of the forgotten pairing `pairID` in `vault` appeared on
    /// the network.
    ///
    /// One session over the stream delivers the close. The appearance is
    /// the stream's alone; Bluetooth has its own.
    internal func forgottenPairingAppeared(_ pairID: Data, in vault: RappDeviceVault) {
      deliverRevocation(of: pairID, along: .stream, in: vault)
    }

    /// A RAPP peripheral appeared over Bluetooth (§4.6 item 6): the
    /// advertisement names no pairing, so each forgotten pairing with no
    /// delivery under way opens one connection to that peripheral and no
    /// other, in turn, whose routing says whether it holds the pairing.
    ///
    /// Every client on a Mac shares one Bluetooth connection to a phone,
    /// and the phone keeps one link per computer: a delivery opened beside
    /// the held session, or beside another delivery, would end that link.
    /// So nothing is opened while the held session dials over Bluetooth or
    /// runs to this peripheral, and the deliveries go one at a time.
    internal func bluetoothPeripheralAppeared(_ peripheral: UUID, in vault: RappDeviceVault) {
      let sessionOverBluetooth =
        sessionSlot.state == .dialing(.bluetooth) || sessionSlot.state == .open(.bluetooth)
      let sessionPeer = sessionOverBluetooth ? bluetoothPeers.preferred : nil
      guard Self.dialsPhones, !revokingOverBluetooth,
        !sessionOverBluetooth || (sessionPeer != nil && sessionPeer != peripheral)
      else { return }
      let waiting = Self.forgottenPairings(in: vault).map(\.pairID).filter { pairID in
        !revocationDeliveries.contains(pairID)
      }
      guard !waiting.isEmpty else { return }
      revocationDeliveries.formUnion(waiting)
      revokingOverBluetooth = true
      Task { @MainActor [weak self] in
        defer {
          self?.revokingOverBluetooth = false
          self?.openHolderSession()
        }
        for pairID in waiting {
          await self?.deliverRevocationNow(
            of: pairID, along: .bluetooth(.only(peripheral)), in: vault)
        }
      }
    }

    /// Opens one session for the forgotten pairing `pairID` along `route`,
    /// the route its phone appeared by, unless a delivery for it is under
    /// way; the phone's echo destroys the pairing.
    ///
    /// The record is read from `vault` again right before the session, so
    /// a pairing an idle sweep destroyed meanwhile sends nothing, and one
    /// whose notice expired is destroyed untold instead (§4.6 item 3).
    private func deliverRevocation(
      of pairID: Data, along route: RappHeldRequesterSession.Route, in vault: RappDeviceVault
    ) {
      guard Self.dialsPhones, !revocationDeliveries.contains(pairID) else { return }
      revocationDeliveries.insert(pairID)
      Task { @MainActor [weak self] in
        await self?.deliverRevocationNow(of: pairID, along: route, in: vault)
      }
    }

    /// Runs the delivery of `pairID` along `route`, already marked under
    /// way, to its end.
    private func deliverRevocationNow(
      of pairID: Data, along route: RappHeldRequesterSession.Route, in vault: RappDeviceVault
    ) async {
      let deliver = revocationDelivery
      let policy: RappRequesterPolicy =
        if case .bluetooth = route { Self.bluetoothPolicy } else { .interactive }
      let clock = RappPlatformClock()
      var delivery = RappRevocationNotice.Delivery.unreached
      if let pair = try? RappPairRecord.loadFromVault(pairId: pairID, vault: vault),
        pair.metadata().forgottenAtMs != nil
      {
        if pair.revocationNoticeExpired(nowMs: clock.wallMilliseconds()) {
          try? RappPairRevocation.revoke(pair, in: vault, clock: clock)
        } else {
          delivery = await deliver(pair, route, policy)
        }
      }
      revocationDeliveries.remove(pairID)
      guard delivery == .acknowledged else {
        followRevocationBacklog(in: vault)
        #if DEBUG
          if delivery == .unacknowledged {
            DevErrorLog.report(
              "forgotten pairing: the phone did not echo its close; kept for its next appearance",
              source: .app)
          }
        #endif
        return
      }
      revocationNoticeDelivered(pairID: pairID, in: vault)
    }
  }
#endif
