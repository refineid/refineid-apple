// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS) || os(iOS)
  import CardCore
  import Foundation
  import RappEngine

  /// The requester's revocation backlog (RAPP v26.11.2 §4.6 item 6, STPA
  /// CC-118).
  ///
  /// A pairing its user forgot, by turning remote use off or by pairing
  /// another phone, is stored forgotten: it serves nothing and keeps its key
  /// only for the `pairing_revoked` close. While any waits, this computer
  /// browses for the hints of those pairings, whatever remote use and the
  /// local reader are, and each time a phone appears for one it opens one
  /// session that sends the close first and waits for the echo; a session
  /// that cannot reach the phone on the stream tries Bluetooth once. The echo
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
      pairIDs: [String: Data]
    ) -> @Sendable (String) -> Void {
      { key in
        guard let pairID = pairIDs[key] else { return }
        Task { @MainActor in
          Self.shared.forgottenPairingAppeared(pairID)
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
        return
      }
      let keys = Set(pairings.map(\.key))
      guard revocationBacklog?.following != keys else { return }
      revocationBacklog?.cancel()
      let browser = RappRevocationBacklogBrowser(
        following: keys,
        classifyingRecord: Self.backlogClassifier(among: pairings),
        onAppeared: Self.backlogAppearanceHandler(
          pairIDs: Dictionary(uniqueKeysWithValues: pairings.map { ($0.key, $0.pairID) })))
      revocationBacklog = browser
      if Self.backlogBrowses {
        browser.start()
      }
    }

    /// The phone of the forgotten pairing `pairID` appeared: one session
    /// delivers the close, unless one already is.
    internal func forgottenPairingAppeared(_ pairID: Data) {
      guard Self.dialsPhones, !revocationDeliveries.contains(pairID),
        let pair = try? RappPairRecord.loadFromVault(pairId: pairID, vault: RappDeviceVault()),
        pair.metadata().forgottenAtMs != nil
      else { return }
      revocationDeliveries.insert(pairID)
      let overBluetooth = Self.dialsOverBluetooth
      let bluetoothPolicy = Self.bluetoothPolicy
      Task { @MainActor [weak self] in
        var delivery = await RappRevocationNotice.deliver(pair, route: .stream)
        if delivery == .unreached, overBluetooth {
          delivery = await RappRevocationNotice.deliver(
            pair, route: .bluetooth(RappBleCentralPeers()), policy: bluetoothPolicy)
        }
        guard let self else { return }
        revocationDeliveries.remove(pairID)
        guard delivery == .acknowledged else {
          #if DEBUG
            DevErrorLog.report(
              "forgotten pairing: the phone did not echo its close; kept for its next appearance",
              source: .app)
          #endif
          return
        }
        revocationNoticeDelivered(pairID: pairID)
      }
    }
  }
#endif
