// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

#if canImport(CoreBluetooth) && canImport(RappEngine)
  @preconcurrency import CoreBluetooth
  import RappEngine

  /// The custodian end of `fi.refineid.rapp.ble`: the GATT server
  /// (RAPP v26.10.29 §5.1, §5.2).
  ///
  /// One peripheral manager publishes the RAPP service once and advertises
  /// only its UUID and a generic name for as long as the server runs. Each
  /// central that enables indications on the channel characteristic opens
  /// a link of its own: the link routes one preamble, then carries frames
  /// written to it and indicated back, and ends when the central disables
  /// indications or the owner closes it. iOS has no call that ends a
  /// central's connection, so a closed link answers the central's writes
  /// with `writeNotPermitted` until it disables indications; no answer is
  /// ever an authentication or encryption error, which would make the
  /// central's system start bonding.
  ///
  /// With a restore identifier, iOS relaunches the app for Bluetooth events
  /// after it ended the process, and the server adopts the published service
  /// instead of adding it again. Centrals still subscribed from the ended
  /// process get closed links: their routing died with it.
  ///
  /// All state is confined to the server's queue; the delegate callbacks
  /// arrive on it.
  public final class RappBleGattPeripheral: NSObject, @unchecked Sendable {
    /// Decides on the server's queue whether a link's routing preamble may
    /// proceed.
    public typealias Admission = @Sendable (RappBleRoutingPurpose, RappBleGattLink) -> Bool

    /// The bootstrap answer served on a read now: the offer while the
    /// custodian can admit an attempt, `pairing-busy` while it cannot; nil
    /// when it serves none.
    public typealias Bootstrap = @Sendable () -> Data?

    /// Decides on the server's queue whether the CPace step 1 written on a
    /// pairing link can be admitted; one that cannot is refused with the
    /// application error (RAPP v26.10.29 §4.2, "Busy Refusal" item 2).
    public typealias AttemptAdmission = @Sendable (RappBleGattLink) -> Bool

    /// One central's link, from its subscription on.
    internal struct LinkState {
      internal let link: RappBleGattLink
      internal let central: CBCentral
      /// The fragment payload capacity; zero once the link is closed.
      internal var capacity: Int
      internal var routed = false
      /// Whether the link was routed for pairing.
      internal var pairing = false
      /// Whether the link's CPace step 1 was admitted.
      internal var attemptAdmitted = false
      internal var open = true
      internal var reassembler = RappBleSarReassembler()
      internal var outbound: [Data] = []
      internal var sendCompletion: CheckedContinuation<Void, any Error>?
    }

    internal let bootstrapAnswer: Bootstrap?
    internal let admits: Admission
    internal let admitsAttempt: AttemptAdmission
    internal let onEvent: @Sendable (RappBleGattServerEvent) -> Void
    internal let queue = DispatchQueue(label: "fi.refineid.rapp-ble-peripheral")
    internal var manager: CBPeripheralManager?
    internal var channel: CBMutableCharacteristic?
    internal var published = false
    internal var links: [UUID: LinkState] = [:]
    internal var finished = false
    private let restoreIdentifier: String?

    /// A custodian serving what `bootstrap` answers at each read (for
    /// pairing; nil when only stored pairings may reconnect), admitting the
    /// preambles `admits` accepts and the CPace step 1 writes
    /// `admitsAttempt` accepts. `restoreIdentifier` names the server to iOS
    /// state restoration; nil for a server that must not outlive its
    /// process.
    @preconcurrency
    public init(
      restoreIdentifier: String?,
      bootstrap: Bootstrap?,
      admits: @escaping Admission,
      admitsAttempt: @escaping AttemptAdmission = { _ in true },
      onEvent: @escaping @Sendable (RappBleGattServerEvent) -> Void
    ) {
      self.restoreIdentifier = restoreIdentifier
      self.bootstrapAnswer = bootstrap
      self.admits = admits
      self.admitsAttempt = admitsAttempt
      self.onEvent = onEvent
      super.init()
    }

    /// The radio state name for a trace.
    internal static func radioState(_ state: CBManagerState) -> RappBleRadioState {
      switch state {
      case .poweredOff:
        .poweredOff

      case .poweredOn:
        .poweredOn

      case .resetting:
        .resetting

      case .unauthorized:
        .unauthorized

      case .unsupported:
        .unsupported

      default:
        .unknown
      }
    }

    /// Publishes and advertises once Bluetooth is powered on.
    public func start() {
      queue.async { [weak self] in
        guard let self, !finished, manager == nil else { return }
        var options: [String: Any] = [CBPeripheralManagerOptionShowPowerAlertKey: false]
        #if os(iOS)
          if let restoreIdentifier {
            options[CBPeripheralManagerOptionRestoreIdentifierKey] = restoreIdentifier
          }
        #endif
        manager = CBPeripheralManager(delegate: self, queue: queue, options: options)
      }
    }

    /// Indicates one protocol frame on `link`, fragment by fragment.
    ///
    /// The attribute protocol allows one outstanding indication, so each
    /// fragment is confirmed before the next leaves (§5.2 backpressure).
    public func send(_ frame: Data, on link: RappBleGattLink) async throws {
      try await withCheckedThrowingContinuation {
        (continuation: CheckedContinuation<Void, any Error>) in
        queue.async { [weak self] in
          guard let self else {
            continuation.resume(throwing: RappBleGattFailure.disconnected)
            return
          }
          enqueue(frame, on: link, continuation: continuation)
        }
      }
    }

    /// Ends `link`: nothing more is delivered from it or sent on it.
    public func close(_ link: RappBleGattLink) {
      queue.async { [weak self] in self?.end(link, .cancelled) }
    }

    /// Stops advertising, withdraws the service, and ends every link.
    public func cancel() {
      queue.async { [weak self] in
        guard let self, !finished else { return }
        finished = true
        for link in links.values.map(\.link) {
          end(link, .cancelled)
        }
        links.removeAll()
        if let manager {
          manager.stopAdvertising()
          manager.removeAllServices()
          onEvent(.trace(.advertisingStopped))
        }
        channel = nil
        published = false
      }
    }

    /// Hands queued fragments to the system until it is full, and settles
    /// the send once the last one is queued.
    internal func drain(_ central: UUID) {
      guard let manager, let channel, var state = links[central] else { return }
      while let fragment = state.outbound.first {
        guard
          manager.updateValue(fragment, for: channel, onSubscribedCentrals: [state.central])
        else {
          links[central] = state
          return
        }
        state.outbound.removeFirst()
      }
      let completion = state.sendCompletion
      state.sendCompletion = nil
      links[central] = state
      completion?.resume()
    }

    /// Adds the service; advertising starts once the system has added it.
    internal func publish() {
      let made = CBMutableCharacteristic(
        type: CBUUID(string: RappBleGattProfile.channelUUIDString),
        properties: [.write, .indicate],
        value: nil,
        permissions: [.writeable])
      let bootstrap = CBMutableCharacteristic(
        type: CBUUID(string: RappBleGattProfile.bootstrapUUIDString),
        properties: [.read],
        value: nil,
        permissions: [.readable])
      let service = CBMutableService(
        type: CBUUID(string: RappBleGattProfile.serviceUUIDString), primary: true)
      service.characteristics = [made, bootstrap]
      channel = made
      published = true
      manager?.add(service)
    }

    internal func advertise() {
      guard let manager, !finished, !manager.isAdvertising else { return }
      manager.startAdvertising([
        CBAdvertisementDataServiceUUIDsKey: [CBUUID(string: RappBleGattProfile.serviceUUIDString)],
        CBAdvertisementDataLocalNameKey: RappBleGattProfile.localName,
      ])
    }

    /// Ends `link` once; the central keeps a closed link until it
    /// disables indications.
    internal func end(_ link: RappBleGattLink, _ failure: RappBleGattFailure) {
      guard var state = links[link.central], state.link == link, state.open else { return }
      state.open = false
      state.routed = false
      state.pairing = false
      state.attemptAdmitted = false
      state.capacity = 0
      state.reassembler.reset()
      state.outbound.removeAll()
      let completion = state.sendCompletion
      state.sendCompletion = nil
      links[link.central] = state
      completion?.resume(throwing: failure)
      onEvent(.trace(.ended(failure)))
      onEvent(.closed(link, failure))
    }

    private func enqueue(
      _ frame: Data,
      on link: RappBleGattLink,
      continuation: CheckedContinuation<Void, any Error>
    ) {
      guard var state = links[link.central], state.link == link, state.open, state.routed else {
        continuation.resume(throwing: RappBleGattFailure.disconnected)
        return
      }
      guard state.sendCompletion == nil else {
        continuation.resume(throwing: RappBleGattFailure.protocolViolation)
        return
      }
      do {
        state.outbound = try RappBleSar.segment(frame, capacity: state.capacity)
      } catch {
        continuation.resume(throwing: RappBleGattFailure.protocolViolation)
        return
      }
      state.sendCompletion = continuation
      links[link.central] = state
      drain(link.central)
    }
  }
#endif
