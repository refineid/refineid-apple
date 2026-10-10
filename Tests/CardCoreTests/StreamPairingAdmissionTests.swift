// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation
import RappEngine
import Testing

@testable import CardCore

/// The card holder's pairing listener closes a connection whose first frame
/// is not the pairing preamble and keeps the offer open (RAPP v26.10.9
/// §2.2.1).
@Suite(.serialized)
internal struct StreamPairingAdmissionTests {
  // MARK: Static Properties

  private static let attempts = 100
  private static let pause = Duration.milliseconds(100)
  private static let stray = Data("not a routing preamble".utf8)

  // MARK: Static Functions

  private static func boundPort(of listener: StreamRelayListener) async throws -> UInt16 {
    for _ in 0..<attempts {
      if let port = listener.port, port != 0 { return port }
      try await Task.sleep(for: pause)
    }
    throw StreamRelayTestFailure.noFrame
  }

  private static func expectAction(
    _ action: StreamPairingAdmission.Action, in gate: StreamPairingAdmissionGate
  ) async throws {
    for _ in 0..<attempts {
      if gate.actions.contains(action) { return }
      try await Task.sleep(for: pause)
    }
    Issue.record("never saw \(action); saw \(gate.actions)")
  }

  // MARK: Functions

  @Test
  internal func thePreambleFirstArrives() {
    var admission = StreamPairingAdmission(preamble: rappStreamPairingPreamble())
    #expect(admission.admit(.connected) == .ignore)
    #expect(admission.admit(.frame(rappStreamPairingPreamble())) == .arrive)
    #expect(admission.admit(.frame(Self.stray)) == .forward)
    #expect(admission.admit(.closed(.disconnected)) == .forward)
  }

  @Test
  internal func aStrayFirstFrameIsRejectedOnceAndItsCloseIsHidden() {
    var admission = StreamPairingAdmission(preamble: rappStreamPairingPreamble())
    #expect(admission.admit(.frame(Self.stray)) == .reject)
    #expect(admission.admit(.frame(rappStreamPairingPreamble())) == .ignore)
    #expect(admission.admit(.closed(.disconnected)) == .ignore)
    #expect(admission.admit(.frame(rappStreamPairingPreamble())) == .arrive)
  }

  @Test
  internal func aConnectionLostBeforeThePreambleKeepsTheOffer() {
    var admission = StreamPairingAdmission(preamble: rappStreamPairingPreamble())
    #expect(admission.admit(.closed(.disconnected)) == .ignore)
    #expect(admission.admit(.closed(.malformedFrame)) == .ignore)
    #expect(admission.admit(.frame(rappStreamPairingPreamble())) == .arrive)
  }

  @Test
  internal func theListenerEndingReachesTheCeremony() {
    var admission = StreamPairingAdmission(preamble: rappStreamPairingPreamble())
    #expect(admission.admit(.closed(.cancelled)) == .forward)
    #expect(admission.admit(.closed(.unreachable)) == .forward)
  }

  /// A stray dialer is turned away and the requester that follows still
  /// arrives on the same listener.
  @Test
  internal func aStrayDialerDoesNotEndTheOffer() async throws {
    let gate = StreamPairingAdmissionGate(preamble: rappStreamPairingPreamble())
    let listener = StreamRelayListener { event in gate.receive(event) }
    gate.listener = listener
    listener.start(displayName: "RefineID admission \(UUID().uuidString.prefix(6))")
    defer { listener.cancel() }
    let port = try await Self.boundPort(of: listener)

    let strayDialer = StreamRelaySession(
      endpointLiterals: ["127.0.0.1:\(port)"], preamble: Self.stray
    ) { _ in
      // the stray dialer only sends its first frame
    }
    strayDialer.start()
    defer { strayDialer.cancel() }
    try await Self.expectAction(.reject, in: gate)
    #expect(listener.isListening, "the stray dialer stopped the listener")

    let requester = StreamRelaySession(
      endpointLiterals: ["127.0.0.1:\(port)"], preamble: rappStreamPairingPreamble()
    ) { _ in
      // the requester only sends its first frame
    }
    requester.start()
    defer { requester.cancel() }
    try await Self.expectAction(.arrive, in: gate)
    #expect(!gate.actions.contains(.forward), "the ceremony saw: \(gate.actions)")
  }
}
