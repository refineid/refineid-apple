// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation
import Network
import Testing

@testable import RefineIDTestHost

/// A requester gathers the custodians it finds before it tries the first,
/// and tries those on the stream first (RAPP v26.11.8 §4.2 item 1,
/// hierarchy specification §3).
@Suite
internal struct PairingEndpointGatheringTests {
  /// What the gathering handed on, in order.
  private final class Handed: @unchecked Sendable {
    private let lock = NSLock()
    private var endpoints: [PairingEndpoint] = []

    var all: [PairingEndpoint] {
      lock.withLock { endpoints }
    }

    func append(_ endpoint: PairingEndpoint) {
      lock.withLock { endpoints.append(endpoint) }
    }
  }

  private static let service = NWEndpoint.service(
    name: "refineid-test", type: "_refineid-stream._tcp", domain: "local.", interface: nil)

  @Test("Gathered custodians are handed on at the release, the stream first")
  internal func streamFirstAtTheRelease() {
    let handed = Handed()
    let gathering = PairingEndpointGathering { endpoint in handed.append(endpoint) }
    let peripheral = UUID()
    gathering.found(.bluetooth(peripheral))
    gathering.found(.stream(Self.service))
    #expect(handed.all.isEmpty, "nothing is tried while gathering")

    gathering.release()
    #expect(handed.all == [.stream(Self.service), .bluetooth(peripheral)])

    let later = UUID()
    gathering.found(.bluetooth(later))
    #expect(handed.all.last == .bluetooth(later), "after the release at once")
  }
}
