// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CryptoKit
import Foundation

/// The plaintext first frame of every connection (RAPP v26.10.29 §2.2.1):
/// `[domain, purpose, routing]`.
///
/// A pairing preamble carries no routing bytes. A session preamble carries
/// a fresh nonce and the tag the pairing's routing key gives it, so no
/// value on the wire stays the same from one dial to the next.
internal enum RoutingPreamble: Equatable {
  case pairing
  case session(SessionRouting)

  internal enum Failure: Error, Equatable {
    case malformed
    case oversized
    case unknownPurpose
  }

  private static let pairingPurpose = "pairing"
  private static let sessionPurpose = "session"
  private static let domainIndex = 0
  private static let purposeIndex = 1
  private static let routingIndex = 2
  private static let elementCount = 3

  /// The largest preamble frame either transport accepts.
  internal static let maximumFrameSize = 64

  /// The preamble domain of a registered transport profile.
  internal static func domain(forProfile profile: String) -> String? {
    switch profile {
    case StreamProfile.name:
      "rapp-stream"

    case RappBleGattProfile.name:
      "rapp-ble"

    default:
      nil
    }
  }

  internal static func decode(_ bytes: Data, profile: String) throws -> Self {
    guard bytes.count <= maximumFrameSize else { throw Failure.oversized }
    guard let expectedDomain = domain(forProfile: profile),
      case .array(let elements) = try? decodeDeterministicCbor(bytes),
      elements.count == elementCount,
      case .text(let domain) = elements[Self.domainIndex],
      case .text(let purpose) = elements[Self.purposeIndex],
      case .bytes(let routing) = elements[Self.routingIndex],
      domain == expectedDomain
    else { throw Failure.malformed }
    switch purpose {
    case pairingPurpose:
      guard routing.isEmpty else { throw Failure.malformed }
      return .pairing

    case sessionPurpose:
      guard let parsed = SessionRouting(routing) else { throw Failure.malformed }
      return .session(parsed)

    default:
      throw Failure.unknownPurpose
    }
  }

  internal func encoded(profile: String) throws -> Data {
    guard let domain = Self.domain(forProfile: profile) else { throw Failure.malformed }
    let purpose: String
    let routing: Data
    switch self {
    case .pairing:
      purpose = Self.pairingPurpose
      routing = Data()

    case .session(let value):
      purpose = Self.sessionPurpose
      routing = value.bytes
    }
    let value = WireValue.array([.text(domain), .text(purpose), .bytes(routing)])
    guard let encoded = try? value.encoded() else { throw Failure.malformed }
    return encoded
  }
}
