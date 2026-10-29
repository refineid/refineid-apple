// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

#if canImport(CoreBluetooth) && canImport(RappEngine)
  @preconcurrency import CoreBluetooth
  import RappEngine

  /// What the server does with the system's callbacks: the radio, the
  /// service, and each central's link, on the server's queue.
  extension RappBleGattPeripheral {
    internal func stateChanged(_ state: CBManagerState) {
      onEvent(.trace(.radio(Self.radioState(state))))
      switch state {
      case .poweredOn:
        guard !finished else { return }
        if published {
          advertise()
        } else {
          publish()
        }

      case .poweredOff, .resetting, .unauthorized, .unsupported:
        // The system drops the published database with the radio.
        for link in links.values.map(\.link) {
          end(link, .bluetoothUnavailable)
        }
        links.removeAll()
        published = false
        channel = nil

      default:
        break
      }
    }

    /// Adopts the service a relaunched process finds still published.
    internal func restore(_ services: [CBMutableService]) {
      let serviceUUID = CBUUID(string: RappBleGattProfile.serviceUUIDString)
      let channelUUID = CBUUID(string: RappBleGattProfile.channelUUIDString)
      guard let service = services.first(where: { $0.uuid == serviceUUID }),
        let restored = service.characteristics?
          .compactMap({ $0 as? CBMutableCharacteristic })
          .first(where: { $0.uuid == channelUUID })
      else { return }
      channel = restored
      published = true
      for central in restored.subscribedCentrals ?? [] {
        let link = RappBleGattLink(identifier: UUID(), central: central.identifier)
        links[central.identifier] = LinkState(
          link: link, central: central, capacity: 0, open: false)
      }
      onEvent(.trace(.servicePublished(restored: true)))
    }

    internal func added(error: (any Error)?) {
      guard error == nil else {
        published = false
        channel = nil
        onEvent(.trace(.serviceNotPublished))
        return
      }
      onEvent(.trace(.servicePublished(restored: false)))
      advertise()
    }

    internal func advertisingStarted(error: (any Error)?) {
      onEvent(.trace(error == nil ? .advertisingStarted : .advertisingFailed))
    }

    internal func subscribed(_ subscriber: CBCentral, to characteristic: CBCharacteristic) {
      guard characteristic.uuid == channel?.uuid, !finished else { return }
      if let previous = links[subscriber.identifier] {
        end(previous.link, .disconnected)
      }
      let attMtu = subscriber.maximumUpdateValueLength + RappBleGattLimit.attHeaderSize
      onEvent(.trace(.subscribed(peer: subscriber.identifier, attMtu: attMtu)))
      let link = RappBleGattLink(identifier: UUID(), central: subscriber.identifier)
      guard let capacity = try? RappBleSar.payloadCapacity(negotiatedAttMtu: attMtu) else {
        links[subscriber.identifier] = LinkState(
          link: link, central: subscriber, capacity: 0, open: false)
        onEvent(.trace(.ended(.attMtuTooSmall)))
        onEvent(.closed(link, .attMtuTooSmall))
        return
      }
      links[subscriber.identifier] = LinkState(link: link, central: subscriber, capacity: capacity)
    }

    internal func unsubscribed(_ subscriber: CBCentral) {
      guard let state = links[subscriber.identifier] else { return }
      onEvent(.trace(.unsubscribed(peer: subscriber.identifier)))
      end(state.link, .disconnected)
      links.removeValue(forKey: subscriber.identifier)
    }

    /// Serves the bootstrap answer of the moment: the offer, or
    /// `pairing-busy` while an attempt cannot be admitted (§4.2, Bootstrap
    /// Read Flow item 1).
    internal func read(_ request: CBATTRequest) {
      guard request.characteristic.uuid == CBUUID(string: RappBleGattProfile.bootstrapUUIDString),
        let answer = bootstrapAnswer?()
      else {
        manager?.respond(to: request, withResult: .readNotPermitted)
        return
      }
      guard request.offset <= answer.count else {
        manager?.respond(to: request, withResult: .invalidOffset)
        return
      }
      request.value = answer.subdata(in: request.offset..<answer.count)
      manager?.respond(to: request, withResult: .success)
    }

    /// Takes the fragments of one write; the answer goes once they are
    /// processed, so a refused preamble is refused in its own answer.
    internal func write(_ requests: [CBATTRequest]) {
      guard let first = requests.first else { return }
      let central = first.central.identifier
      // A write before indications are enabled, on a closed link, from two
      // centrals at once, or anywhere but the channel is refused.
      guard links[central]?.open == true,
        requests.allSatisfy({ request in
          request.characteristic.uuid == channel?.uuid && request.central.identifier == central
        })
      else {
        manager?.respond(to: first, withResult: .writeNotPermitted)
        if let state = links[central] { end(state.link, .protocolViolation) }
        return
      }
      for request in requests {
        guard request.offset == 0, let value = request.value else {
          if let state = links[central] { end(state.link, .protocolViolation) }
          manager?.respond(to: first, withResult: .writeNotPermitted)
          return
        }
        let result = receive(value, from: central)
        guard result == .success else {
          manager?.respond(to: first, withResult: result)
          return
        }
      }
      manager?.respond(to: first, withResult: .success)
    }

    internal func readyToUpdate() {
      for (central, state) in links where state.sendCompletion != nil {
        drain(central)
      }
    }

    /// Takes one fragment; the write's answer, other than success when it
    /// ended the link.
    private func receive(_ fragment: Data, from central: UUID) -> CBATTError.Code {
      guard var state = links[central] else { return .writeNotPermitted }
      let now = RappPlatformClock().monotonicMilliseconds()
      let message: Data?
      do {
        message = try state.reassembler.receive(
          fragment, capacity: state.capacity, nowMilliseconds: now)
      } catch {
        end(state.link, .reassemblyFailed)
        return .writeNotPermitted
      }
      links[central] = state
      guard let message else {
        armTimer(for: state.link)
        return .success
      }
      return deliver(message, on: central)
    }

    /// Accepts one complete frame in the phase the link is in.
    ///
    /// The first frame on a pairing link is CPace step 1; one the custodian
    /// cannot admit is refused with the application error, and the
    /// requester reads the bootstrap characteristic again (§4.2, "Busy
    /// Refusal" item 2).
    private func deliver(_ message: Data, on central: UUID) -> CBATTError.Code {
      guard var state = links[central] else { return .writeNotPermitted }
      guard state.routed else {
        guard let purpose = RappBleRoutingPurpose(preamble: message),
          admits(purpose, state.link)
        else {
          onEvent(.trace(.preambleRefused(peer: central)))
          end(state.link, .routingRefused)
          return .writeNotPermitted
        }
        state.routed = true
        state.pairing = purpose == .pairing
        links[central] = state
        onEvent(.routed(state.link))
        return .success
      }
      if state.pairing, !state.attemptAdmitted {
        guard admitsAttempt(state.link) else {
          end(state.link, .attemptRefused)
          return CBATTError.Code(rawValue: BleAttValues.applicationError)
            ?? .unlikelyError
        }
        state.attemptAdmitted = true
        links[central] = state
      }
      onEvent(.frame(state.link, message))
      return .success
    }

    private func armTimer(for link: RappBleGattLink) {
      queue.asyncAfter(
        deadline: .now() + .milliseconds(Int(RappBleSar.reassemblyTimeoutMilliseconds))
      ) { [weak self] in
        guard let self, var state = links[link.central], state.link == link, state.open else {
          return
        }
        do {
          try state.reassembler.checkTimer(
            nowMilliseconds: RappPlatformClock().monotonicMilliseconds())
          links[link.central] = state
        } catch {
          end(link, .reassemblyFailed)
        }
      }
    }
  }
#endif
