// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS) && REFINEID_REMOTE_CARD

  import CardCore
  import Foundation
  import RappEngine
  import Testing

  @testable import RefineIDTestHost

  /// A phone that forgets this computer (RAPP v26.11.2 §4.6 item 4) drops
  /// the pairing here and leaves remote use on: the row names the phone
  /// above the pairing prompt.
  extension RemoteUseSwitchTests {
    @Test("The phone forgetting this computer leaves remote use on and names the phone")
    internal func revokedPairingKeepsRemoteUseOn() throws {
      let rig = Self.rig()
      let registry = PersistentTokenRegistry.shared
      let vault = RappDeviceVault()
      rig.remoteUse.toggle()
      defer {
        registry.phoneThatForgot = nil
        registry.refreshPairing(in: vault)
        rig.remoteUse.stop()
      }
      let pairID = try Self.storedPairing(in: vault).metadata().pairId

      registry.holderRevoked(pairID: pairID, in: vault)

      #expect(rig.remoteUse.isOn, "only the holder turns remote use off")
      #expect(RemoteAccessGate.isEnabled)
      #expect(rig.moves.value == [.turnedOn])
      #expect(try vault.loadPair(pairID: pairID) == nil, "the pairing is dropped")
      #expect(registry.phoneThatForgot == PairRecordFixture.phoneName)
      let facts = RequesterFacts(
        availability: .noCard, warnsUnavailableCard: false, readerConnected: false,
        cardPresent: false, remoteUse: rig.remoteUse.isOn,
        phonePaired: registry.pairedPhoneID != nil,
        phoneThatForgot: registry.phoneThatForgot)
      #expect(IdentityLine.derive(facts) == .phoneForgot(PairRecordFixture.phoneName))
    }
  }
#endif
