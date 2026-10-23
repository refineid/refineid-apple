// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS) && REFINEID_REMOTE_CARD && REFINEID_STREAM_TRANSPORT

  import CardCore
  import CoreBluetooth
  import CryptoKit
  import dnssd
  import Foundation
  import Network
  import RappEngine
  import Testing

  @testable import RefineID

  /// The Mac's remote-use switch (hierarchy specification §5.2, STPA §27):
  /// off by default and kept, nothing remote while it is off, and turning
  /// it off ends everything remote at once while the pairing stays.
  @Suite(.serialized)
  @MainActor
  internal struct RemoteUseSwitchTests {
    /// A watch that records what the switch asks of it, and reports what a
    /// test says it found.
    @MainActor
    private final class RecordingWatch: RemoteUseWatch {
      private(set) var starts = 0
      private(set) var stops = 0
      private var report: (@MainActor (RemoteUseBlockage?) -> Void)?

      var isWatching: Bool {
        report != nil
      }

      func start(report: @escaping @MainActor (RemoteUseBlockage?) -> Void) {
        starts += 1
        self.report = report
      }

      func stop() {
        stops += 1
        report = nil
      }

      func found(_ blockage: RemoteUseBlockage?) {
        report?(blockage)
      }
    }

    /// How often the switch told the requester it moved.
    @MainActor
    private final class FollowCount {
      var value = 0
    }

    /// A switch on recording watches, and what it told the requester.
    private struct Rig {
      let remoteUse: RemoteUseSwitch
      let bluetooth: RecordingWatch
      let localNetwork: RecordingWatch
      let follows: FollowCount
    }

    private static let phone = "Alpha iPhone"

    /// When the test pairing was made, in milliseconds since the Unix
    /// epoch.
    private static let pairingCreation: UInt64 = 1_000

    /// When a test pairing is revoked; the vault records no time for it.
    private static let revocationTime: UInt64 = 0

    private static func rig() -> Rig {
      let bluetooth = RecordingWatch()
      let localNetwork = RecordingWatch()
      let follows = FollowCount()
      let remoteUse = RemoteUseSwitch(bluetooth: bluetooth, localNetwork: localNetwork) {
        follows.value += 1
      }
      return Rig(
        remoteUse: remoteUse, bluetooth: bluetooth, localNetwork: localNetwork, follows: follows)
    }

    /// A requester's pairing with a phone of its own keys, stored in
    /// `vault`.
    private static func storedPairing(in vault: RappDeviceVault) throws -> RappPairRecord {
      let local = Curve25519.KeyAgreement.PrivateKey()
      let remote = Curve25519.KeyAgreement.PrivateKey()
      let pairing = try RappSameAccountPairBuilder.makePairRecord(
        localStaticPrivate: local.rawRepresentation,
        localStaticPublic: local.publicKey.rawRepresentation,
        localRole: .requester,
        remotePublicKey: remote.publicKey.rawRepresentation,
        createdAtMilliseconds: pairingCreation)
      try vault.insertPair(pairID: pairing.metadata().pairId, record: try pairing.encodedBytes())
      return pairing
    }

    // MARK: The switch

    @Test("Remote use starts off, and a launch with it off asks macOS for nothing")
    internal func startsOffAndAsksForNothing() {
      let rig = Self.rig()
      #expect(!rig.remoteUse.isOn)
      rig.remoteUse.start()
      #expect(rig.bluetooth.starts == 0)
      #expect(rig.localNetwork.starts == 0)
      #expect(rig.follows.value == 0)

      // The app's own switch holds no Bluetooth manager and runs no browse.
      let shared = RemoteUseSwitch.shared
      #expect(!shared.isOn)
      #expect(!shared.bluetoothWatch.isWatching)
      #expect(!shared.localNetworkWatch.isWatching)
    }

    @Test("Turning remote use on starts both watches; off stops them and forgets what they found")
    internal func turningOnAndOff() {
      let rig = Self.rig()
      defer { rig.remoteUse.turn(on: false) }

      rig.remoteUse.toggle()
      #expect(rig.remoteUse.isOn)
      #expect(PersistentTokenRegistry.remoteUseOn)
      #expect(rig.bluetooth.starts == 1)
      #expect(rig.localNetwork.starts == 1)
      #expect(rig.follows.value == 1)

      rig.bluetooth.found(.bluetoothOff)
      #expect(rig.remoteUse.blockage == .bluetoothOff)

      rig.remoteUse.toggle()
      #expect(!rig.remoteUse.isOn)
      #expect(!PersistentTokenRegistry.remoteUseOn)
      #expect(rig.bluetooth.stops == 1)
      #expect(rig.localNetwork.stops == 1)
      #expect(rig.follows.value == 2)
      #expect(rig.remoteUse.blockage == nil)
      #expect(!rig.bluetooth.isWatching)
      #expect(!rig.localNetwork.isWatching)
    }

    @Test("The choice is kept: a switch made later reads it")
    internal func choiceIsKept() {
      let first = Self.rig().remoteUse
      defer { first.turn(on: false) }
      first.turn(on: true)
      let later = Self.rig().remoteUse
      #expect(later.isOn)
      later.start()
      first.turn(on: false)
      #expect(!Self.rig().remoteUse.isOn)
    }

    @Test("A refused permission is named before Bluetooth that is merely off")
    internal func blockagePriority() {
      let rig = Self.rig()
      rig.remoteUse.turn(on: true)
      defer { rig.remoteUse.turn(on: false) }

      rig.bluetooth.found(.bluetoothOff)
      #expect(rig.remoteUse.blockage == .bluetoothOff)
      rig.localNetwork.found(.localNetworkNotAllowed)
      #expect(rig.remoteUse.blockage == .localNetworkNotAllowed)
      rig.localNetwork.found(nil)
      #expect(rig.remoteUse.blockage == .bluetoothOff)
      rig.bluetooth.found(.bluetoothNotAllowed)
      #expect(rig.remoteUse.blockage == .bluetoothNotAllowed)
      rig.bluetooth.found(nil)
      #expect(rig.remoteUse.blockage == nil)
    }

    // MARK: The state it shows

    @Test("Connected needs an open session; a blockage shows only while none is open")
    internal func stateDerivation() {
      #expect(RemoteUseState.derive(isOn: false, sessionOpen: false, blockage: nil) == .off)
      #expect(RemoteUseState.derive(isOn: false, sessionOpen: true, blockage: nil) == .off)
      #expect(
        RemoteUseState.derive(isOn: false, sessionOpen: false, blockage: .bluetoothOff) == .off)
      #expect(RemoteUseState.derive(isOn: true, sessionOpen: false, blockage: nil) == .waiting)
      #expect(RemoteUseState.derive(isOn: true, sessionOpen: true, blockage: nil) == .connected)
      for blockage in [
        RemoteUseBlockage.bluetoothOff, .bluetoothNotAllowed, .localNetworkNotAllowed,
      ] {
        #expect(
          RemoteUseState.derive(isOn: true, sessionOpen: false, blockage: blockage)
            == .blocked(blockage))
        #expect(
          RemoteUseState.derive(isOn: true, sessionOpen: true, blockage: blockage) == .connected)
      }
    }

    @Test("Each state has its symbol and colour, and only blocked takes a warning colour")
    internal func stateLooks() {
      #expect(RemoteUseState.off.symbolName == "key.radiowaves.forward.slash")
      #expect(RemoteUseState.off.tone == .neutral)
      #expect(RemoteUseState.waiting.symbolName == "key.radiowaves.forward")
      #expect(RemoteUseState.waiting.tone == .neutral)
      #expect(RemoteUseState.connected.symbolName == "key.radiowaves.forward")
      #expect(RemoteUseState.connected.tone == .connected)
      let blocked = RemoteUseState.blocked(.bluetoothOff)
      #expect(blocked.symbolName == "key.radiowaves.forward.slash")
      #expect(blocked.tone == .warning)
    }

    @Test("Each state is named in words, a blockage with its cause")
    internal func stateWords() {
      #expect(RemoteUseState.label == String(localized: "Remote Access"))
      #expect(RemoteUseState.off.value == String(localized: "Off"))
      #expect(RemoteUseState.waiting.value == String(localized: "On"))
      #expect(RemoteUseState.connected.value == String(localized: "Phone connected"))
      for blockage in [
        RemoteUseBlockage.bluetoothOff, .bluetoothNotAllowed, .localNetworkNotAllowed,
      ] {
        let state = RemoteUseState.blocked(blockage)
        #expect(state.value == String(localized: "Blocked: \(blockage.cause)"))
        #expect(state.help.contains(RemoteUseState.label))
        #expect(state.help.contains(blockage.cause))
      }
      #expect(RemoteUseState.off.help.contains(RemoteUseState.off.value))
    }

    // MARK: The watches

    @Test("Bluetooth off or refused blocks remote use; on, or not yet known, does not")
    internal func bluetoothReadiness() {
      #expect(BluetoothReadinessWatch.blockage(for: .poweredOff) == .bluetoothOff)
      #expect(BluetoothReadinessWatch.blockage(for: .unauthorized) == .bluetoothNotAllowed)
      #expect(BluetoothReadinessWatch.blockage(for: .poweredOn) == nil)
      #expect(BluetoothReadinessWatch.blockage(for: .unknown) == nil)
      #expect(BluetoothReadinessWatch.blockage(for: .resetting) == nil)
    }

    @Test("A browse waiting on the privacy policy is refused; a running browse is allowed")
    internal func localNetworkPermission() {
      let policyDenied = NWError.dns(DNSServiceErrorType(kDNSServiceErr_PolicyDenied))
      let otherFailure = NWError.dns(DNSServiceErrorType(kDNSServiceErr_NoSuchRecord))
      #expect(LocalNetworkPermissionWatch.permission(in: .waiting(policyDenied)) == .refused)
      #expect(LocalNetworkPermissionWatch.permission(in: .failed(policyDenied)) == .refused)
      #expect(LocalNetworkPermissionWatch.permission(in: .ready) == .allowed)
      #expect(LocalNetworkPermissionWatch.permission(in: .waiting(otherFailure)) == nil)
      #expect(LocalNetworkPermissionWatch.permission(in: .setup) == nil)
      #expect(LocalNetworkPermissionWatch.permission(in: .cancelled) == nil)
    }

    // MARK: The requester while off

    @Test("Off, nothing browses or dials, the extension is refused and no identity is offered")
    internal func offFollowsNothing() async throws {
      let registry = PersistentTokenRegistry.shared
      let initialPresence = CardPresence.shared.isReaderCardPresent
      let vault = RappDeviceVault()
      let pairing = try Self.storedPairing(in: vault)
      let pairID = pairing.metadata().pairId
      try vault.selectPair(pairID: pairID)
      defer {
        try? vault.clearSelectedPair()
        try? vault.revokePair(pairID: pairID, revokedAtMilliseconds: Self.revocationTime)
        CardPresence.shared.setReaderCardPresentForTesting(initialPresence)
      }
      CardPresence.shared.setReaderCardPresentForTesting(false)
      #expect(!PersistentTokenRegistry.remoteUseOn)
      #expect(!PersistentTokenRegistry.followsPhone)

      // Launch with remote use off.
      registry.start()
      #expect(registry.presence == nil)
      #expect(registry.settleDialTask == nil)
      #expect(registry.transportPolicy.nextDial == nil)
      registry.openHolderSession()
      #expect(registry.holderSession == nil)

      // The token extension's handed-over operation is refused.
      let handoff = RappHeldSessionHandoff.Request(
        pairID: pairID, operation: .readAuthenticationCertificate)
      #expect(await registry.carry(handoff) == .failed(.peerNotFound))

      // No identity of the phone's is offered, and signing stays local.
      let signer = try SignerCertificateFixtures.makeSigner(for: .ecdsaSha256)
      #expect(PersistentTokenRegistry.publish(signer.certificate) == .remoteUseOff)
      #expect(registry.certificateDER == nil)
      #expect(!DocumentSigner.usesRappSigning)
    }

    @Test("Turning off closes the session and withdraws the identity at once; the pairing stays")
    internal func turningOffEndsEverythingRemote() throws {
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

      // Remote use as it was before the switch moved: a session up over
      // Bluetooth, the phone in sight, its card's identity offered.
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

      // Remote use is off in a test run; the registry follows the switch.
      registry.remoteUseChanged()

      #expect(registry.holderSession == nil)
      #expect(!registry.holderSessionOpen)
      #expect(!registry.holderInSight)
      #expect(registry.presence == nil)
      #expect(registry.redialTask == nil)
      // Withdrawn at once: no grace is left to run.
      #expect(registry.certificateDER == nil)
      #expect(registry.holderLine == nil)
      #expect(registry.offerLapseTask == nil)
      // The pairing stays, so turning remote use on resumes without a code.
      #expect(registry.pairedPhone == Self.phone)
      #expect(PersistentTokenRegistry.pairedPhoneID(in: vault) == pairID)
    }
  }

#endif
