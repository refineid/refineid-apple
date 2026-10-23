// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS) && REFINEID_REMOTE_CARD && REFINEID_STREAM_TRANSPORT

  import CardCore
  import CryptoKit
  import Foundation
  import RappEngine
  import Testing

  @testable import RefineID

  /// Turning remote use off, and quitting while it is on, is this
  /// computer's withdrawal (RAPP v26.10.22 §4.5 item 8): the session ends
  /// with `service_withdrawn`, a dial under way ends without a notice, and
  /// the pairing stays.
  extension RemoteUseSwitchTests {
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

    @Test("Quitting with remote use on turns it off and waits on the session's withdrawal")
    internal func quittingWithdraws() async throws {
      let registry = PersistentTokenRegistry.shared
      // Turning on stands in for the registry's dial; turning off reaches
      // the registry as the app's own switch does.
      let remoteUse = RemoteUseSwitch(bluetooth: IdleWatch(), localNetwork: IdleWatch()) {
        if !PersistentTokenRegistry.remoteUseOn {
          PersistentTokenRegistry.shared.remoteUseChanged()
        }
      }
      #expect(
        QuitWithdrawal.begin(remoteUse: remoteUse, registry: registry) == nil,
        "with remote use off, quitting waits on nothing")

      remoteUse.turn(on: true)
      defer { remoteUse.turn(on: false) }
      try Self.holdUnstartedSession(in: registry)

      let closes = try #require(QuitWithdrawal.begin(remoteUse: remoteUse, registry: registry))
      #expect(!remoteUse.isOn)
      #expect(!PersistentTokenRegistry.remoteUseOn)
      #expect(registry.holderSession == nil)
      #expect(await !closes.value, "a session never dialled has no close to send")
    }
  }

#endif
