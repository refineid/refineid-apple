// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CardCore
import Testing

extension VirtualIDCardTests {
  @Test
  internal func testForgettingIdentityChangesOnlyDeviceState() async {
    let card = VirtualIDCard(scenario: .registeredNearField)
    let original = await card.inspect().card

    await card.forgetDeviceState()
    let forgotten = await card.inspect()

    expectState(forgotten.card == original, sourceLocation: #_sourceLocation)
    expectState(forgotten.device == (VirtualIDCard.DeviceState()), sourceLocation: #_sourceLocation)
  }

  @Test
  internal func testSuccessfulRegistrationPublishesOnlyVirtualDeviceState() async {
    let card = VirtualIDCard(scenario: .activatedNearField)
    _ = await card.connect(cardAccessNumber: "123456")

    let result = await card.register()

    guard case .success(let state) = result else {
      Issue.record("registration did not succeed")
      return
    }
    expectState(state.device.cachedIdentity, sourceLocation: #_sourceLocation)
    expectState(state.device.tokenRegistered, sourceLocation: #_sourceLocation)
  }

  @Test
  internal func testEveryScenarioAndFaultPresetBuildsDeterministicState() {
    for scenario in VirtualIDCard.Scenario.allCases {
      let first = scenario.snapshot
      let second = scenario.snapshot

      expectState(
        first == second, context: "\(scenario.rawValue) was not deterministic",
        sourceLocation: #_sourceLocation)
      #expect(
        first.card.pin1.attemptsRemaining <= RetryCount.pristineAllowance,
        sourceLocation: #_sourceLocation)
      #expect(
        first.card.pin2.attemptsRemaining <= RetryCount.pristineAllowance,
        sourceLocation: #_sourceLocation)
      #expect(
        first.card.puk.attemptsRemaining <= RetryCount.pristineAllowance,
        sourceLocation: #_sourceLocation)
    }

    for preset in VirtualIDCard.FaultPreset.allCases {
      if preset == .noFault {
        #expect(preset.faults.isEmpty, "\(preset.rawValue) has unexpected faults")
      } else {
        #expect(!preset.faults.isEmpty, "\(preset.rawValue) has no fault")
      }
    }
  }

  @Test
  internal func testStateReplacementResetAndFaultQueueControls() async {
    let card = VirtualIDCard()
    let initial = await card.inspect()
    expectState(
      initial == VirtualIDCard.Scenario.factoryFreshNearField.snapshot,
      sourceLocation: #_sourceLocation)

    await card.replace(with: VirtualIDCard.Scenario.registeredNearField.snapshot)
    let registered = await card.inspect()
    expectState(registered.device.tokenRegistered, sourceLocation: #_sourceLocation)

    await card.reset(to: .absent)
    let absent = await card.inspect()
    #expect(!absent.card.cardPresent, sourceLocation: #_sourceLocation)

    await card.enqueue(
      VirtualIDCard.Fault(
        operation: .any,
        phase: .beforeCommand,
        effect: .timeout,
        remainingOccurrences: 0))
    let enqueued = await card.inspect()
    expectState(
      (enqueued.faults.first?.remainingOccurrences) == 1, sourceLocation: #_sourceLocation)

    await card.clearFaults()
    let cleared = await card.inspect()
    expectState(cleared.faults.isEmpty, sourceLocation: #_sourceLocation)
  }

  @Test
  internal func testConnectionFailureClearsTransientStateAndDoesNotPersistCAN() async {
    let card = VirtualIDCard(scenario: .activatedNearField)
    _ = await card.connect(cardAccessNumber: "123456")
    var state = await card.inspect()
    state.card.cardPresent = false
    await card.replace(with: state)

    let removedConnection = await card.connect(cardAccessNumber: "123456")
    expectState(removedConnection == (.unavailable(.cardRemoved)), sourceLocation: #_sourceLocation)
    let removedState = await card.inspect()
    expectState(
      removedState.device.connectedCardAccessNumber == nil, sourceLocation: #_sourceLocation)

    state = VirtualIDCard.Scenario.activatedNearField.snapshot
    state.faults = [
      VirtualIDCard.Fault(
        operation: .connect,
        phase: .afterCardExecution,
        effect: .timeout)
    ]
    await card.replace(with: state)

    let timedOutConnection = await card.connect(cardAccessNumber: "123456")
    expectState(timedOutConnection == (.unavailable(.timeout)), sourceLocation: #_sourceLocation)
    let failed = await card.inspect()
    expectState(failed.device.connectedCardAccessNumber == nil, sourceLocation: #_sourceLocation)
    expectState(failed.device.storedCardAccessNumber == nil, sourceLocation: #_sourceLocation)

    await card.reset(to: .activatedReader)
    guard case .connected = await card.connect(cardAccessNumber: "not-a-CAN") else {
      Issue.record("reader connection incorrectly required a wireless CAN")
      return
    }
    let reader = await card.inspect()
    expectState(reader.device.connectedCardAccessNumber == nil, sourceLocation: #_sourceLocation)
    expectState(reader.device.storedCardAccessNumber == nil, sourceLocation: #_sourceLocation)
  }

  @Test
  internal func testMalformedCANAndDisconnectedReaderAreUnavailableSafely() async {
    for offered in ["", "12345", "1234567", "12a456"] {
      let card = VirtualIDCard(scenario: .activatedNearField)
      let result = await card.connect(cardAccessNumber: offered)
      expectState(result == .incorrectCardAccessNumber, sourceLocation: #_sourceLocation)
      let state = await card.inspect()
      expectState(state.device == (VirtualIDCard.DeviceState()), sourceLocation: #_sourceLocation)
    }

    var state = VirtualIDCard.Scenario.activatedReader.snapshot
    state.card.readerConnected = false
    state.device.connectedCardAccessNumber = "stale"
    let card = VirtualIDCard(snapshot: state)
    let result = await card.connect(cardAccessNumber: "")
    expectState(result == (.unavailable(.readerDisconnected)), sourceLocation: #_sourceLocation)
    let disconnected = await card.inspect()
    expectState(
      disconnected.device.connectedCardAccessNumber == nil, sourceLocation: #_sourceLocation)
  }

  @Test
  internal func testCredentialProbeCoversReportsAndFailures() async {
    let reporting = VirtualIDCard(scenario: .activatedReader)
    let report = await reporting.probeCredentials()
    expectState(
      report
        == (.report(
          VirtualIDCard.RetryReport(
            pin1: RetryCount.pristineAllowance,
            pin2: RetryCount.pristineAllowance,
            puk: RetryCount.pristineAllowance))),
      sourceLocation: #_sourceLocation)

    let disconnected = VirtualIDCard(scenario: .activatedNearField)
    let disconnectedResult = await disconnected.probeCredentials()
    expectState(
      disconnectedResult == (.unavailable(.connectionLost)), sourceLocation: #_sourceLocation)

    for phase in VirtualIDCard.FaultPhase.allCases {
      var state = VirtualIDCard.Scenario.activatedReader.snapshot
      state.faults = [
        VirtualIDCard.Fault(
          operation: .probeCredentials,
          phase: phase,
          effect: .malformedResponse)
      ]
      let unreadable = VirtualIDCard(snapshot: state)
      let result = await unreadable.probeCredentials()
      expectState(result == .unreadable, sourceLocation: #_sourceLocation)
    }

    var state = VirtualIDCard.Scenario.activatedReader.snapshot
    state.faults = VirtualIDCard.FaultPreset.readerFailsCounterQuery.faults
    let failedReader = VirtualIDCard(snapshot: state)
    let failure = await failedReader.probeCredentials()
    expectState(failure == (.unavailable(.readerDisconnected)), sourceLocation: #_sourceLocation)
    let failedState = await failedReader.inspect()
    expectState(!failedState.card.readerConnected, sourceLocation: #_sourceLocation)
    #expect(!failedState.card.cardPresent, sourceLocation: #_sourceLocation)
  }

  @Test
  internal func testMalformedPINChangeNeverConsumesRetryOrFault() async {
    var state = VirtualIDCard.Scenario.activatedReader.snapshot
    state.faults = [
      VirtualIDCard.Fault(
        operation: .changePIN1,
        phase: .beforeCommand,
        effect: .timeout)
    ]
    let card = VirtualIDCard(snapshot: state)

    let malformedCurrent = await card.changePIN1(current: "bad", new: "9876")
    #expect(malformedCurrent.outcome == .invalidEntry, sourceLocation: #_sourceLocation)
    let unchanged = await card.changePIN1(current: "1234", new: "1234")
    #expect(unchanged.outcome == .invalidEntry, sourceLocation: #_sourceLocation)
    let malformedNew = await card.changePIN2(
      current: "123456",
      new: "short")
    #expect(malformedNew.outcome == .invalidEntry, sourceLocation: #_sourceLocation)
    let untouched = await card.inspect()
    #expect(
      untouched.card.pin1.attemptsRemaining == RetryCount.pristineAllowance,
      sourceLocation: #_sourceLocation)
    expectState(untouched.faults.count == 1, sourceLocation: #_sourceLocation)

    let timedOut = await card.changePIN1(current: "1234", new: "9876")
    #expect(timedOut.outcome == (.transportFailure(.timeout)), sourceLocation: #_sourceLocation)
  }

  @Test
  internal func testPIN2RetryFloorMatrix() async {
    for attempts in UInt8(0)...RetryCount.pristineAllowance {
      var state = VirtualIDCard.Scenario.activatedReader.snapshot
      state.card.pin2.attemptsRemaining = attempts
      let card = VirtualIDCard(snapshot: state)

      let result = await card.changePIN2(current: "000000", new: "987654")

      switch attempts {
      case 0:
        #expect(result.outcome == .blocked, sourceLocation: #_sourceLocation)
        #expect(result.snapshot.card.pin2.attemptsRemaining == 0, sourceLocation: #_sourceLocation)

      case 1...lowAttemptRefusalCeiling:
        #expect(
          result.outcome == (.refusedLowAttempts(remaining: attempts)),
          sourceLocation: #_sourceLocation)
        #expect(
          result.snapshot.card.pin2.attemptsRemaining == attempts, sourceLocation: #_sourceLocation)

      default:
        #expect(
          result.outcome == (.rejected(remaining: attempts - 1)), sourceLocation: #_sourceLocation)
        #expect(
          result.snapshot.card.pin2.attemptsRemaining == (attempts - 1),
          sourceLocation: #_sourceLocation)
      }
    }
  }
}
