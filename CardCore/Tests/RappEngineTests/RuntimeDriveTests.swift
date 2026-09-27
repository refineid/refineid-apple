// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.
//
// Liveness, attribution, framing, and policy against the tables

import Foundation
import Testing

@testable import RappEngine

// MARK: - Fixtures

/// Two channels wired to each other, as a completed handshake would leave them.
internal func makeChannelPair() -> (RappSecureChannel, RappSecureChannel) {
  let firstKey = Data(repeating: RuntimeFixture.firstKeyFill, count: NoiseSizes.keyLength)
  let secondKey = Data(repeating: RuntimeFixture.secondKeyFill, count: NoiseSizes.keyLength)
  var initiatorSend = NoiseCipherState()
  var initiatorReceive = NoiseCipherState()
  var responderSend = NoiseCipherState()
  var responderReceive = NoiseCipherState()
  initiatorSend.initializeKey(firstKey)
  responderReceive.initializeKey(firstKey)
  responderSend.initializeKey(secondKey)
  initiatorReceive.initializeKey(secondKey)
  return (
    RappSecureChannel(send: initiatorSend, receive: initiatorReceive),
    RappSecureChannel(send: responderSend, receive: responderReceive)
  )
}

internal let testSessionIdentifier = Data(
  repeating: RuntimeFixture.sessionFill, count: WireLimits.sessionIdentifier)

internal func challenge(_ byte: UInt8) -> PingChallenge {
  guard let value = PingChallenge(Data(repeating: byte, count: PingChallenge.byteCount)) else {
    fatalError("fixed challenge fixture is the registered size")
  }
  return value
}

internal let testPolicy = LivenessConfiguration(
  baseIntervalMilliseconds: RuntimeFixture.baseInterval,
  responseTimeoutMilliseconds: RuntimeFixture.responseTimeout,
  maximumIntervalMilliseconds: RuntimeFixture.maximumInterval,
  maximumJitterMilliseconds: 100,
  maximumMisses: RuntimeFixture.maximumMisses)

/// A connected pairing with a healthy session, as pairing leaves it.
internal func establishedState(role: EndpointRole) -> RappState {
  var state = RappState(role: role)
  state.pairing = .pairedConnected
  state.session = .healthy
  return state
}

internal func makeRuntime(
  role: EndpointRole,
  channel: RappSecureChannel
) -> EndpointRuntime {
  guard
    let tracker = try? LivenessTracker(
      configuration: testPolicy, nowMilliseconds: 0)
  else { fatalError("test policy is valid") }
  return EndpointRuntime(
    sessionIdentifier: testSessionIdentifier,
    channel: channel,
    state: establishedState(role: role),
    liveness: tracker)
}

// The scenario runs as one continuous drive, because that is what it proves:
// each step depends on the state the previous one left, and a peer answers a
// real predecessor rather than a fixture. Splitting it into separate tests
// would thread that state through setup and stop testing the sequence.
@Suite("RAPP endpoint runtime")
internal struct RuntimeDriveTests {
  @Test("Liveness, attribution, framing, and policy against the tables")
  internal func run() throws {
    try livenessEchoProof()
    try missDeadlineClosesSession()
    checkingBlocksAdmission()
    try backoffSchedule()
    try jitterBounded()
    tamperedFrameClosesSession()
    outOfPhaseEndsPairing()
    try wrongSequenceEndsPairing()
    droppedFrameClosesSessionOnly()
    try framingLimits()
    restoreActionsMatchTables()
    integrityFailureCloseActions()
    staleReferenceRace()
    failurePolicyTable()
    try negativeControlMismatchedEcho()
  }
}
