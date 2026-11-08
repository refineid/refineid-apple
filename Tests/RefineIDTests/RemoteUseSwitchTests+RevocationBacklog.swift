// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS) && REFINEID_REMOTE_CARD

  import CardCore
  import Foundation
  import RappEngine
  import Testing

  @testable import RefineIDTestHost

  /// The sessions a test's backlog opened, each answered as the test says.
  private final class BacklogDeliveries: @unchecked Sendable {
    private let lock = NSLock()
    private var opened: [(pairID: Data, route: RappHeldRequesterSession.Route)] = []
    private var release: CheckedContinuation<Void, Never>?
    private let holds: Bool
    private let answer: RappRevocationNotice.Delivery

    init(holding holds: Bool, answer: RappRevocationNotice.Delivery = .acknowledged) {
      self.holds = holds
      self.answer = answer
    }

    /// The routes of the sessions opened for `pairID`.
    func routes(for pairID: Data) -> [RappHeldRequesterSession.Route] {
      lock.withLock { opened.filter { $0.pairID == pairID }.map(\.route) }
    }

    /// The phone's answer: its echo, once the test lets a held one go.
    func deliver(_ pairID: Data, _ route: RappHeldRequesterSession.Route) async
      -> RappRevocationNotice.Delivery
    {
      lock.withLock { opened.append((pairID, route)) }
      if holds {
        await withCheckedContinuation { continuation in
          lock.withLock { release = continuation }
        }
      }
      return answer
    }

    func letGo() {
      let waiting = lock.withLock { () -> CheckedContinuation<Void, Never>? in
        defer { release = nil }
        return release
      }
      waiting?.resume()
    }
  }

  /// The revocation backlog finds a phone that appears only over Bluetooth
  /// (RAPP v26.11.8 §4.6 item 6): one connection per appearance, the echo
  /// destroys the pairing, and the scan stops with the backlog.
  extension RemoteUseSwitchTests {
    /// A forgotten pairing in `vault`, followed by the backlog, whose
    /// sessions go to `deliveries`.
    private static func forgottenInBacklog(
      in vault: RappDeviceVault,
      registry: PersistentTokenRegistry,
      deliveries: BacklogDeliveries
    ) throws -> RappPairRecord {
      let pairing = try recentPairing(in: vault)
      try RappPairRevocation.forget(pairing, in: vault, clock: RappPlatformClock())
      registry.revocationDelivery = { pair, route, _ in
        await deliveries.deliver(pair.metadata().pairId, route)
      }
      registry.followRevocationBacklog(in: vault)
      return pairing
    }

    /// Lets the main actor run the backlog's delivery until `done` holds.
    private static func settle(_ done: () -> Bool) async {
      for _ in 0..<unchainedDestructionMarginMilliseconds where !done() {
        await Task.yield()
        try? await Task.sleep(for: .milliseconds(1))
      }
    }

    /// Puts back the backlog's own sessions.
    private static func restoreDelivery(_ registry: PersistentTokenRegistry) {
      registry.revocationDelivery = { pair, route, policy in
        await RappRevocationNotice.deliver(pair, route: route, policy: policy)
      }
    }

    @Test(
      "A phone that appears only over Bluetooth hears the close, and its echo destroys the pairing")
    internal func bluetoothOnlyAppearanceDelivers() async throws {
      let registry = PersistentTokenRegistry.shared
      let vault = RappDeviceVault()
      let deliveries = BacklogDeliveries(holding: false)
      let pairing = try Self.forgottenInBacklog(
        in: vault, registry: registry, deliveries: deliveries)
      defer {
        Self.restoreDelivery(registry)
        Self.destroy([pairing], in: vault, registry: registry)
      }
      #expect(registry.revocationBluetoothWatch != nil, "the backlog scans while it waits")
      let phone = UUID()

      registry.bluetoothPeripheralAppeared(phone, in: vault)
      await Self.settle { (try? vault.loadPair(pairID: pairing.metadata().pairId)) == nil }

      #expect(
        deliveries.routes(for: pairing.metadata().pairId)
          == [.bluetooth(.only(phone))])
      #expect(try vault.loadPair(pairID: pairing.metadata().pairId) == nil, "the echo destroys it")
      #expect(registry.revocationBacklog == nil)
      #expect(registry.revocationBluetoothWatch == nil, "an empty backlog scans no more")
    }

    @Test("No close is opened to the peripheral that carries the held session")
    internal func noDeliveryBesideTheHeldSession() async throws {
      let registry = PersistentTokenRegistry.shared
      let vault = RappDeviceVault()
      let deliveries = BacklogDeliveries(holding: false)
      let pairing = try Self.forgottenInBacklog(
        in: vault, registry: registry, deliveries: deliveries)
      let savedSlot = registry.sessionSlot
      let savedPeers = registry.bluetoothPeers
      defer {
        registry.sessionSlot = savedSlot
        registry.bluetoothPeers = savedPeers
        Self.restoreDelivery(registry)
        Self.destroy([pairing], in: vault, registry: registry)
      }
      let sessionPhone = UUID()
      registry.bluetoothPeers.routed(sessionPhone)
      _ = registry.sessionSlot.dial(over: .bluetooth, at: .now)
      registry.sessionSlot.established()

      registry.bluetoothPeripheralAppeared(sessionPhone, in: vault)
      #expect(deliveries.routes(for: pairing.metadata().pairId).isEmpty)

      // Another phone in sight is tried, and only that one.
      let otherPhone = UUID()
      registry.bluetoothPeripheralAppeared(otherPhone, in: vault)
      await Self.settle { !deliveries.routes(for: pairing.metadata().pairId).isEmpty }
      #expect(deliveries.routes(for: pairing.metadata().pairId) == [.bluetooth(.only(otherPhone))])
    }

    @Test("A peripheral in sight while its close is under way opens no second connection")
    internal func noSecondDialWhileUnderWay() async throws {
      let registry = PersistentTokenRegistry.shared
      let vault = RappDeviceVault()
      let deliveries = BacklogDeliveries(holding: true)
      let pairing = try Self.forgottenInBacklog(
        in: vault, registry: registry, deliveries: deliveries)
      defer {
        Self.restoreDelivery(registry)
        Self.destroy([pairing], in: vault, registry: registry)
      }
      let phone = UUID()

      registry.bluetoothPeripheralAppeared(phone, in: vault)
      let pairID = pairing.metadata().pairId
      await Self.settle { deliveries.routes(for: pairID).count == 1 }
      registry.bluetoothPeripheralAppeared(phone, in: vault)
      #expect(deliveries.routes(for: pairID).count == 1, "one connection per appearance")

      deliveries.letGo()
      await Self.settle { (try? vault.loadPair(pairID: pairID)) == nil }
      #expect(deliveries.routes(for: pairID).count == 1)
    }

    @Test("The Bluetooth watcher stops once the backlog is empty")
    internal func watcherStopsWithTheBacklog() throws {
      let registry = PersistentTokenRegistry.shared
      let vault = RappDeviceVault()
      let pairing = try Self.forgottenInBacklog(
        in: vault, registry: registry, deliveries: BacklogDeliveries(holding: false))
      defer { Self.restoreDelivery(registry) }
      #expect(registry.revocationBluetoothWatch != nil)

      try RappPairRevocation.revoke(
        pairID: pairing.metadata().pairId, in: vault, clock: RappPlatformClock())
      registry.followRevocationBacklog(in: vault)

      #expect(registry.revocationBacklog == nil)
      #expect(registry.revocationBluetoothWatch == nil)
    }

    @Test("A session record's appearance opens one stream session, and the echo stops the backlog")
    internal func streamAppearanceDeliversOverTheStreamAlone() async throws {
      let registry = PersistentTokenRegistry.shared
      let vault = RappDeviceVault()
      let deliveries = BacklogDeliveries(holding: false)
      let pairing = try Self.forgottenInBacklog(
        in: vault, registry: registry, deliveries: deliveries)
      defer {
        Self.restoreDelivery(registry)
        Self.destroy([pairing], in: vault, registry: registry)
      }
      let pairID = pairing.metadata().pairId
      #expect(registry.revocationBacklog != nil)

      registry.forgottenPairingAppeared(pairID, in: vault)
      await Self.settle { (try? vault.loadPair(pairID: pairID)) == nil }

      #expect(deliveries.routes(for: pairID) == [.stream])
      #expect(registry.revocationBacklog == nil, "the browser stops after the last echo")
      #expect(registry.revocationBluetoothWatch == nil)
    }

    @Test("A stream appearance that does not reach the phone tries no other route")
    internal func unreachedStreamTriesNoBluetooth() async throws {
      let registry = PersistentTokenRegistry.shared
      let vault = RappDeviceVault()
      let deliveries = BacklogDeliveries(holding: false, answer: .unreached)
      let pairing = try Self.forgottenInBacklog(
        in: vault, registry: registry, deliveries: deliveries)
      defer {
        Self.restoreDelivery(registry)
        Self.destroy([pairing], in: vault, registry: registry)
      }
      let pairID = pairing.metadata().pairId

      registry.forgottenPairingAppeared(pairID, in: vault)
      await Self.settle { deliveries.routes(for: pairID).count == 1 }
      await Self.settle { !registry.revocationDeliveries.contains(pairID) }

      #expect(deliveries.routes(for: pairID) == [.stream], "one route per appearance")
      #expect(Self.forgotten(pairing, in: vault), "kept for the next appearance")
    }

    @Test("A forgotten pairing whose idle expiry passed before its session is destroyed untold")
    internal func expiredBeforeTheSessionSendsNothing() async throws {
      let registry = PersistentTokenRegistry.shared
      let vault = RappDeviceVault()
      let deliveries = BacklogDeliveries(holding: false)
      let pairing = try Self.storedPairing(in: vault)
      defer {
        Self.restoreDelivery(registry)
        Self.destroy([pairing], in: vault, registry: registry)
      }
      try RappPairRevocation.forget(pairing, in: vault, clock: RappPlatformClock())
      registry.revocationDelivery = { pair, route, _ in
        await deliveries.deliver(pair.metadata().pairId, route)
      }
      let pairID = pairing.metadata().pairId

      registry.forgottenPairingAppeared(pairID, in: vault)
      await Self.settle { (try? vault.loadPair(pairID: pairID)) == nil }

      #expect(deliveries.routes(for: pairID).isEmpty, "no close leaves with an expired key")
      #expect(try vault.loadPair(pairID: pairID) == nil)
    }
  }

#endif
