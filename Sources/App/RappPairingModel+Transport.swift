// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CardCore
import RappEngine

extension RappPairingModel {
  #if os(iOS) && REFINEID_LOCAL_CARD
    /// The ceremony's frames on the pairing link `link`.
    private static func bluetoothTransport(_ link: RappBleGattLink) -> RappClosureFrameTransport {
      RappClosureFrameTransport(
        sender: { frame in
          try await PhonePersistentTokenRelay.shared.sendPairingFrame(frame, on: link)
        },
        closer: {
          await PhonePersistentTokenRelay.shared.closePairingLink(link)
        })
    }
  #endif

  internal func makeTransport(
    relay: PairingRelay
  ) -> RappClosureFrameTransport {
    RappClosureFrameTransport(
      sender: { [weak relay] frame in
        guard let relay else {
          throw PersistentRelayTransportError.disconnected
        }
        try relay.send(frame)
      },
      closer: { [weak relay] in relay?.cancel() },
      connectionEnder: { [weak relay] frame in
        relay?.endConnection(answering: frame) ?? false
      }
    )
  }

  /// Answers a stream pairing connection busy while another connection
  /// holds the offer, keeping the listener for the next one (RAPP v26.11.2
  /// §4.2, "Busy Refusal").
  internal func refuseStreamConnection(
    relay: PairingRelay, coordinator: RappPairingCoordinator
  ) {
    #if DEBUG
      DevErrorLog.report(
        "pairing: a stream connection answered busy, another holds the offer", source: .app)
    #endif
    if let busy = coordinator.busyAnswer(), relay.endConnection(answering: busy) { return }
    relay.disconnect()
  }

  #if os(iOS) && REFINEID_LOCAL_CARD
    /// Serves this phone's offer on its GATT server beside the stream
    /// (RAPP v26.11.2 §4.2, §5.2).
    ///
    /// The link that claimed the offer runs the ceremony; another link's
    /// CPace step 1 is refused busy at the server.
    internal func offerOverBluetooth(
      _ coordinator: RappPairingCoordinator, claim: PairingConnectionClaim
    ) {
      let offer = BluetoothPairingOffer(
        bootstrap: { try? coordinator.bootstrapAnswer() },
        admitsAttempt: { coordinator.admitsAttempt() },
        claim: claim)
      PhonePersistentTokenRelay.shared.offerPairingOverBluetooth(offer) { [weak self] event in
        self?.receive(event, coordinator: coordinator, claim: claim)
      }
    }

    private func receive(
      _ event: BluetoothPairingEvent,
      coordinator: RappPairingCoordinator,
      claim: PairingConnectionClaim
    ) {
      guard self.coordinator === coordinator else { return }
      switch event {
      case .routed(let link):
        guard claim.holds(.bluetooth(link)) else { return }
        let transport = Self.bluetoothTransport(link)
        deliverInOrder {
          guard await coordinator.attach(transport, transportProfile: RappBleGattProfile.name)
          else {
            claim.release(.bluetooth(link))
            #if DEBUG
              DevErrorLog.report(
                "pairing: a Bluetooth link waits, another holds the offer", source: .app)
            #endif
            return
          }
          await coordinator.transportConnected()
        }

      case .frame(let link, let frame):
        guard claim.holds(.bluetooth(link)) else { return }
        deliverInOrder { await coordinator.receive(frame) }

      case .closed(let link):
        guard !isFinished, claim.holds(.bluetooth(link)) else { return }
        deliverInOrder {
          await coordinator.transportClosed()
          claim.release(.bluetooth(link))
        }
      }
    }
  #endif
}
