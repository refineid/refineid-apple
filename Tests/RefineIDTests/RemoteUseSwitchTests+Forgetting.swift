// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS) && REFINEID_REMOTE_CARD && REFINEID_STREAM_TRANSPORT

  import CardCore
  import Foundation
  import RappEngine
  import Testing

  @testable import RefineID

  /// The holder's click off forgets every pairing (RAPP v26.10.22 §4.6 item
  /// 6, CC-100); a stop withdraws and keeps them (§4.5 item 8).
  extension RemoteUseSwitchTests {
    /// Gives `registry` a session over `pairing` as remote use had it: up
    /// over Bluetooth, the phone in sight, its card's identity offered.
    private static func holdOpenSession(
      over pairing: RappPairRecord, in registry: PersistentTokenRegistry
    ) {
      registry.holderSession = RappHeldRequesterSession(pair: pairing) { _ in
        // A session never started reports nothing worth keeping.
      }
      registry.holderSessionToken = UUID()
      registry.sessionSlot = RequesterSessionSlot()
      let dialed = registry.sessionSlot.dial(over: .bluetooth, at: .now)
      #expect(dialed)
      registry.sessionSlot.established()
      registry.holderOverBluetooth = true
      registry.holderIsAdvertising = true
      registry.certificateDER = Data("certificate".utf8)
      registry.holderLine = "TEST HOLDER"
      #expect(registry.holderSessionOpen)
    }

    @Test("The holder's click off revokes the session's pairing and forgets every pairing")
    internal func clickOffForgetsEveryPairing() async throws {
      let registry = PersistentTokenRegistry.shared
      let vault = RappDeviceVault()
      let pairing = try Self.storedPairing(in: vault)
      let other = try Self.storedPairing(in: vault)
      let pairID = pairing.metadata().pairId
      RappPairNames.remember(Self.phone, pairID: pairID)
      defer {
        RappPairNames.forget(pairID: pairID)
        registry.refreshPairing(in: vault)
      }
      registry.refreshPairing(in: vault)
      registry.phoneThatForgot = Self.phone
      Self.holdOpenSession(over: pairing, in: registry)

      registry.forgetEveryPairing(in: vault)

      // Everything remote stops at once.
      #expect(registry.holderSession == nil)
      #expect(!registry.holderSessionOpen)
      #expect(!registry.holderInSight)
      #expect(registry.presence == nil)
      #expect(registry.certificateDER == nil)
      #expect(registry.holderLine == nil)
      #expect(registry.phoneThatForgot == nil)
      let forgetting = try #require(registry.forgetting, "the open session's close leaves first")
      await forgetting.value

      // Then every pairing is gone with its key and its name.
      #expect(registry.forgetting == nil)
      #expect(try vault.activePairIDs().isEmpty)
      #expect(try vault.loadPair(pairID: other.metadata().pairId) == nil)
      #expect(RappPairNames.name(forPairID: pairID) == nil)
      #expect(registry.pairedPhone == nil)
      #expect(PersistentTokenRegistry.pairedPhoneID(in: vault) == nil)
    }

    @Test("With no session open, the click off destroys every pairing at once and tells nobody")
    internal func clickOffWithoutSessionOwesNothing() throws {
      let registry = PersistentTokenRegistry.shared
      let vault = RappDeviceVault()
      _ = try Self.storedPairing(in: vault)
      registry.refreshPairing(in: vault)
      defer { registry.refreshPairing(in: vault) }

      registry.forgetEveryPairing(in: vault)

      #expect(registry.forgetting == nil)
      #expect(try vault.activePairIDs().isEmpty)
      #expect(registry.pairedPhone == nil)
    }

    @Test("A stop withdraws at once and keeps the pairing")
    internal func stopWithdrawsAndKeepsThePairing() throws {
      let registry = PersistentTokenRegistry.shared
      let vault = RappDeviceVault()
      let pairing = try Self.storedPairing(in: vault)
      let pairID = pairing.metadata().pairId
      RappPairNames.remember(Self.phone, pairID: pairID)
      defer {
        RappPairNames.forget(pairID: pairID)
        try? vault.revokePair(pairID: pairID, revokedAtMilliseconds: Self.revocationTime)
        registry.refreshPairing(in: vault)
      }
      registry.refreshPairing(in: vault)
      Self.holdOpenSession(over: pairing, in: registry)

      registry.remoteUseChanged(.stopped)

      #expect(registry.holderSession == nil)
      #expect(!registry.holderSessionOpen)
      #expect(!registry.holderInSight)
      #expect(registry.presence == nil)
      #expect(registry.redialTask == nil)
      // Withdrawn at once: no grace is left to run.
      #expect(registry.certificateDER == nil)
      #expect(registry.holderLine == nil)
      #expect(registry.offerLapseTask == nil)
      #expect(registry.forgetting == nil)
      // The pairing stays, so the next launch restores remote use on.
      #expect(registry.pairedPhone == Self.phone)
      #expect(PersistentTokenRegistry.pairedPhoneID(in: vault) == pairID)
    }
  }

#endif
