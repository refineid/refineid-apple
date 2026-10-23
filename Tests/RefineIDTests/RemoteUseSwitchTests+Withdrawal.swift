// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS) && REFINEID_REMOTE_CARD && REFINEID_STREAM_TRANSPORT

  import CardCore
  import CryptoKit
  import Foundation
  import RappEngine
  import Testing

  @testable import RefineID

  /// A card in this Mac's reader, and quitting while remote use is on, is
  /// this computer's withdrawal (RAPP v26.10.22 §4.5 item 8): the session
  /// ends with `service_withdrawn`, a dial under way ends without a notice,
  /// and the pairing stays.
  extension RemoteUseSwitchTests {
    /// How the switch told the requester it moved.
    @MainActor
    private final class MoveLog {
      var value: [RemoteUseSwitch.Move] = []
    }

    /// A watch that asks for nothing and finds nothing.
    @MainActor
    private final class IdleWatch: RemoteUseWatch {
      private var report: (@MainActor (RemoteUseBlockage?) -> Void)?

      var isWatching: Bool {
        report != nil
      }

      func start(report: @escaping @MainActor (RemoteUseBlockage?) -> Void) {
        self.report = report
      }

      func stop() {
        report = nil
      }
    }

    /// When the test pairing was made, in milliseconds since the Unix
    /// epoch.
    private static let withdrawalPairingCreation: UInt64 = 1_000

    /// A requester's pairing with a phone of its own keys, stored nowhere.
    private static func unstoredPairing() throws -> RappPairRecord {
      let local = Curve25519.KeyAgreement.PrivateKey()
      let remote = Curve25519.KeyAgreement.PrivateKey()
      return try RappSameAccountPairBuilder.makePairRecord(
        localStaticPrivate: local.rawRepresentation,
        localStaticPublic: local.publicKey.rawRepresentation,
        localRole: .requester,
        remotePublicKey: remote.publicKey.rawRepresentation,
        createdAtMilliseconds: withdrawalPairingCreation)
    }

    /// Gives the registry a session that was never started, as one still
    /// being dialled.
    private static func holdUnstartedSession(in registry: PersistentTokenRegistry) throws {
      registry.holderSession = RappHeldRequesterSession(pair: try unstoredPairing()) { _ in
        // A session never started reports nothing worth keeping.
      }
      registry.holderSessionToken = UUID()
    }

    @Test("Withdrawing ends the session and every waiting dial; a dial under way sends nothing")
    internal func withdrawingEndsTheSession() async throws {
      let registry = PersistentTokenRegistry.shared
      #expect(registry.withdrawHolderSession() == nil, "no session, nothing to withdraw")

      try Self.holdUnstartedSession(in: registry)
      registry.redialTask = Task {
        // A dial waiting for its turn.
      }
      registry.settleDialTask = Task {
        // A dial waiting for Bonjour to settle.
      }
      let closes = try #require(registry.withdrawHolderSession())
      #expect(registry.holderSession == nil)
      #expect(registry.holderSessionToken == nil)
      #expect(registry.redialTask == nil)
      #expect(registry.settleDialTask == nil)
      #expect(await !closes.value, "a session never dialled has no close to send")
    }

    @Test("Quitting with remote use on stops it, keeps the pairing, and waits on the withdrawal")
    internal func quittingWithdraws() async throws {
      let registry = PersistentTokenRegistry.shared
      // Turning on stands in for the registry's dial; a stop reaches the
      // registry as the app's own switch does.
      let moves = MoveLog()
      let remoteUse = RemoteUseSwitch(bluetooth: IdleWatch(), localNetwork: IdleWatch()) { move in
        moves.value.append(move)
        if move == .stopped {
          PersistentTokenRegistry.shared.remoteUseChanged(move)
        }
      }
      #expect(
        QuitWithdrawal.begin(remoteUse: remoteUse, registry: registry) == nil,
        "with remote use off, quitting waits on nothing")

      remoteUse.toggle()
      defer { remoteUse.stop() }
      try Self.holdUnstartedSession(in: registry)

      let closes = try #require(QuitWithdrawal.begin(remoteUse: remoteUse, registry: registry))
      #expect(!remoteUse.isOn)
      #expect(!PersistentTokenRegistry.remoteUseOn)
      #expect(moves.value == [.turnedOn, .stopped], "quitting forgets no pairing")
      #expect(registry.holderSession == nil)
      #expect(await !closes.value, "a session never dialled has no close to send")
    }

    @Test("A card in this Mac's reader suspends remote use; the switch and the pairing stay")
    internal func localCardSuspends() throws {
      let registry = PersistentTokenRegistry.shared
      let initialPresence = CardPresence.shared.isReaderCardPresent
      let initialBluetooth = registry.bluetoothUsable
      let vault = RappDeviceVault()
      let pairing = try Self.unstoredPairing()
      let pairID = pairing.metadata().pairId
      try vault.insertPair(pairID: pairID, record: try pairing.encodedBytes())
      RemoteAccessGate.setEnabled(true)
      defer {
        RemoteAccessGate.setEnabled(false)
        registry.remoteUseChanged(.stopped)
        CardPresence.shared.setReaderCardPresentForTesting(initialPresence)
        registry.bluetoothUsable = initialBluetooth
      }
      CardPresence.shared.setReaderCardPresentForTesting(false)
      registry.bluetoothUsable = true
      try Self.holdUnstartedSession(in: registry)
      registry.certificateDER = Data("certificate".utf8)

      CardPresence.shared.setReaderCardPresentForTesting(true)
      #expect(registry.holderSession == nil)
      #expect(registry.certificateDER == nil)
      #expect(registry.transportPolicy.nextDial == nil)
      #expect(PersistentTokenRegistry.remoteUseOn, "suspension leaves the switch on")
      #expect(PersistentTokenRegistry.pairedPhoneID(in: vault) == pairID)

      CardPresence.shared.setReaderCardPresentForTesting(false)
      #expect(PersistentTokenRegistry.remoteUseOn)
      #expect(registry.transportPolicy.nextDial == .bluetooth, "remote use resumes as it was")
    }
  }

#endif
