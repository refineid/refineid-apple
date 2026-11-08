// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(iOS) && REFINEID_LOCAL_CARD
  import CardCore
  import Foundation
  import os
  import RappEngine

  extension BluetoothPairingEvent {
    /// The server's event about a pairing link; nil for any other link's.
    ///
    /// A closed pairing link leaves the set of pairing links.
    internal init?(
      _ event: RappBleGattServerEvent, routing: OSAllocatedUnfairLock<BluetoothRouting>
    ) {
      switch event {
      case .routed(let link):
        guard routing.withLock({ $0.pairingLinks.contains(link) }) else { return nil }
        self = .routed(link)

      case .frame(let link, let frame):
        guard routing.withLock({ $0.pairingLinks.contains(link) }) else { return nil }
        self = .frame(link, frame)

      case .closed(let link, _):
        guard routing.withLock({ $0.pairingLinks.remove(link) != nil }) else { return nil }
        self = .closed(link)

      case .trace:
        return nil
      }
    }
  }

  /// The phone's pairing offer on its GATT server (RAPP v26.11.2 §4.2,
  /// §5.2): served beside the stream listener while the phone shows a
  /// code, whether or not it serves any pairing yet.
  @MainActor
  extension PhonePersistentTokenRelay {
    /// Whether the phone offers a pairing over Bluetooth now.
    internal var isOfferingPairingOverBluetooth: Bool {
      bluetoothRouting.withLock { $0.pairingOffer != nil }
    }

    /// Serves `offer` on the Bluetooth server, starting the server when it
    /// is not running, and hands each pairing link's events to `handler`.
    internal func offerPairingOverBluetooth(
      _ offer: BluetoothPairingOffer,
      handler: @escaping (BluetoothPairingEvent) -> Void
    ) {
      guard RemoteAccessGate.isEnabled, SupportedCardTransports.offersNearField else { return }
      bluetoothPairingHandler = handler
      bluetoothRouting.withLock { $0.pairingOffer = offer }
      guard bluetoothServer == nil else { return }
      startBluetoothServing(PhoneStreamPairContext.resolveAll(vault: vault))
    }

    /// Stops serving the pairing offer and ends its links; the server
    /// stops with it when no pairing is served.
    internal func withdrawPairingOverBluetooth() {
      bluetoothPairingHandler = nil
      let links = bluetoothRouting.withLock { routing in
        routing.pairingOffer = nil
        defer { routing.pairingLinks.removeAll() }
        return routing.pairingLinks
      }
      for link in links {
        bluetoothServer?.close(link)
      }
      if !hasUsablePair() {
        stopBluetoothServing()
      }
    }

    /// Sends one pairing frame on `link`.
    internal func sendPairingFrame(_ frame: Data, on link: RappBleGattLink) async throws {
      guard let server = bluetoothServer else { throw RappBleGattFailure.disconnected }
      try await server.send(frame, on: link)
    }

    /// Ends the pairing link `link`.
    internal func closePairingLink(_ link: RappBleGattLink) {
      bluetoothServer?.close(link)
    }
  }
#endif
