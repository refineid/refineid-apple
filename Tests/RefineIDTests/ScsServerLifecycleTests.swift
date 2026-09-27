// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Network
import Synchronization
import XCTest

@testable import RefineID

@MainActor
internal final class ScsServerLifecycleTests: XCTestCase {
  internal func testListenerStopsConnectionsAndRestartsWithoutCertificateTrust() async throws {
    let ready = expectation(description: "Loopback listener ready")
    let stopped = expectation(description: "Loopback listener stopped")
    let restarted = expectation(description: "Loopback listener restarted")
    let secondStop = expectation(description: "Restarted listener stopped")
    let counts = Mutex((ready: 0, stopped: 0))
    let server = ScsServer(
      makeParameters: {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        return parameters
      },
      observeState: { state in
        counts.withLock { counts in
          switch state {
          case .ready:
            counts.ready += 1
            (counts.ready == 1 ? ready : restarted).fulfill()
          case .cancelled:
            counts.stopped += 1
            (counts.stopped == 1 ? stopped : secondStop).fulfill()
          default:
            break
          }
        }
      }
    )
    server.start()
    await fulfillment(of: [ready], timeout: 5)
    let port = try XCTUnwrap(server.localPort)
    let connected = expectation(description: "Client connected")
    let disconnected = expectation(description: "Client disconnected by disabling server")
    let client = NWConnection(host: "127.0.0.1", port: port, using: .tcp)
    defer { client.cancel() }
    client.stateUpdateHandler = { state in
      if case .ready = state { connected.fulfill() }
    }
    client.start(queue: .global())
    await fulfillment(of: [connected], timeout: 5)
    client.receive(minimumIncompleteLength: 1, maximumLength: 1) { _, _, complete, error in
      if complete || error != nil { disconnected.fulfill() }
    }
    server.stop()
    await fulfillment(of: [stopped, disconnected], timeout: 5)
    XCTAssertNil(server.localPort)
    server.start()
    await fulfillment(of: [restarted], timeout: 5)
    server.stop()
    await fulfillment(of: [secondStop], timeout: 5)
  }
}
