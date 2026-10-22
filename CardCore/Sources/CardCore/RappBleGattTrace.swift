// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// One step of a `fi.refineid.rapp.ble` link, for a development trace.
///
/// The link reports these as values and logs nothing itself; an owner that
/// writes them anywhere does so only in a development build. A peer is the
/// identifier Core Bluetooth assigns it on this device, which the owner
/// uses to tell advertisers apart and ``line`` leaves out.
public enum RappBleGattTrace: Sendable, Equatable {
  /// Advertising could not start.
  case advertisingFailed
  /// Advertising the service UUID started.
  case advertisingStarted
  /// Advertising stopped.
  case advertisingStopped
  /// The connection is up with this ATT MTU, read before the first write.
  case connected(peer: UUID, attMtu: Int)
  /// The requester connects to this advertiser.
  case connecting(peer: UUID)
  /// An advertiser of the RAPP service was seen.
  case discovered(peer: UUID, rssi: Int)
  /// The link ended for this reason.
  case ended(RappBleGattFailure)
  /// The channel characteristic was found and indications were asked for.
  case indicationsRequested
  /// The routing preamble was written and acknowledged.
  case preambleAccepted
  /// The custodian refused a central's routing preamble.
  case preambleRefused(peer: UUID)
  /// The radio's state, as Core Bluetooth reported it.
  case radio(RappBleRadioState)
  /// Scanning for the RAPP service started.
  case scanning
  /// Publishing the service failed.
  case serviceNotPublished
  /// The service was published, or adopted from the process iOS relaunched.
  case servicePublished(restored: Bool)
  /// A central enabled indications; its link starts here, over the ATT MTU
  /// the two systems negotiated.
  case subscribed(peer: UUID, attMtu: Int)
  /// A central disabled indications or went away.
  case unsubscribed(peer: UUID)

  /// The step as one line naming the step and its measurements, and no
  /// peer.
  public var line: String {
    switch self {
    case .advertisingFailed:
      "advertising failed"

    case .advertisingStarted:
      "advertising"

    case .advertisingStopped:
      "advertising stopped"

    case .connected(_, let attMtu):
      "connected, ATT MTU \(attMtu)"

    case .connecting:
      "connecting"

    case .discovered(_, let rssi):
      "advertiser seen, RSSI \(rssi)"

    case .ended(let failure):
      "link ended: \(failure)"

    case .indicationsRequested:
      "indications requested"

    case .preambleAccepted:
      "preamble accepted"

    case .preambleRefused:
      "preamble refused"

    case .radio(let state):
      "radio \(state)"

    case .scanning:
      "scanning"

    case .serviceNotPublished:
      "service not published"

    case .servicePublished(let restored):
      restored ? "service restored" : "service published"

    case .subscribed(_, let attMtu):
      "subscribed, ATT MTU \(attMtu)"

    case .unsubscribed:
      "unsubscribed"
    }
  }
}
