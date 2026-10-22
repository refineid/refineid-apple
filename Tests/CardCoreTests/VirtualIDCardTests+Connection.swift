// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CardCore
import XCTest

extension VirtualIDCardTests {
  internal func testForgettingIdentityChangesOnlyDeviceState() async {
    let card = VirtualIDCard(scenario: .registeredNearField)
    let original = await card.inspect().card

    await card.forgetDeviceState()
    let forgotten = await card.inspect()

    XCTAssertEqual(forgotten.card, original)
    XCTAssertEqual(forgotten.device, VirtualIDCard.DeviceState())
  }

  internal func testSuccessfulRegistrationPublishesOnlyVirtualDeviceState() async {
    let card = VirtualIDCard(scenario: .activatedNearField)
    _ = await card.connect(cardAccessNumber: "123456")

    let result = await card.register()

    guard case .success(let state) = result else {
      XCTFail("registration did not succeed")
      return
    }
    XCTAssertTrue(state.device.cachedIdentity)
    XCTAssertTrue(state.device.tokenRegistered)
  }

  internal func testEveryScenarioAndFaultPresetBuildsDeterministicState() {
    for scenario in VirtualIDCard.Scenario.allCases {
      let first = scenario.snapshot
      let second = scenario.snapshot

      XCTAssertEqual(first, second, "\(scenario.rawValue) was not deterministic")
      XCTAssertLessThanOrEqual(
        first.card.pin1.attemptsRemaining,
        RetryCount.pristineAllowance)
      XCTAssertLessThanOrEqual(
        first.card.pin2.attemptsRemaining,
        RetryCount.pristineAllowance)
      XCTAssertLessThanOrEqual(
        first.card.puk.attemptsRemaining,
        RetryCount.pristineAllowance)
    }

    for preset in VirtualIDCard.FaultPreset.allCases {
      if preset == .noFault {
        XCTAssertTrue(preset.faults.isEmpty)
      } else {
        XCTAssertFalse(preset.faults.isEmpty, "\(preset.rawValue) has no fault")
      }
    }
  }

  internal func testStateReplacementResetAndFaultQueueControls() async {
    let card = VirtualIDCard()
    let initial = await card.inspect()
    XCTAssertEqual(
      initial,
      VirtualIDCard.Scenario.factoryFreshNearField.snapshot)

    await card.replace(with: VirtualIDCard.Scenario.registeredNearField.snapshot)
    let registered = await card.inspect()
    XCTAssertTrue(registered.device.tokenRegistered)

    await card.reset(to: .absent)
    let absent = await card.inspect()
    XCTAssertFalse(absent.card.cardPresent)

    await card.enqueue(
      VirtualIDCard.Fault(
        operation: .any,
        phase: .beforeCommand,
        effect: .timeout,
        remainingOccurrences: 0))
    let enqueued = await card.inspect()
    XCTAssertEqual(enqueued.faults.first?.remainingOccurrences, 1)

    await card.clearFaults()
    let cleared = await card.inspect()
    XCTAssertTrue(cleared.faults.isEmpty)
  }

  internal func testConnectionFailureClearsTransientStateAndDoesNotPersistCAN() async {
    let card = VirtualIDCard(scenario: .activatedNearField)
    _ = await card.connect(cardAccessNumber: "123456")
    var state = await card.inspect()
    state.card.cardPresent = false
    await card.replace(with: state)

    let removedConnection = await card.connect(cardAccessNumber: "123456")
    XCTAssertEqual(removedConnection, .unavailable(.cardRemoved))
    let removedState = await card.inspect()
    XCTAssertNil(removedState.device.connectedCardAccessNumber)

    state = VirtualIDCard.Scenario.activatedNearField.snapshot
    state.faults = [
      VirtualIDCard.Fault(
        operation: .connect,
        phase: .afterCardExecution,
        effect: .timeout)
    ]
    await card.replace(with: state)

    let timedOutConnection = await card.connect(cardAccessNumber: "123456")
    XCTAssertEqual(timedOutConnection, .unavailable(.timeout))
    let failed = await card.inspect()
    XCTAssertNil(failed.device.connectedCardAccessNumber)
    XCTAssertNil(failed.device.storedCardAccessNumber)

    await card.reset(to: .activatedReader)
    guard case .connected = await card.connect(cardAccessNumber: "not-a-CAN") else {
      XCTFail("reader connection incorrectly required a wireless CAN")
      return
    }
    let reader = await card.inspect()
    XCTAssertNil(reader.device.connectedCardAccessNumber)
    XCTAssertNil(reader.device.storedCardAccessNumber)
  }

  internal func testMalformedCANAndDisconnectedReaderAreUnavailableSafely() async {
    for offered in ["", "12345", "1234567", "12a456"] {
      let card = VirtualIDCard(scenario: .activatedNearField)
      let result = await card.connect(cardAccessNumber: offered)
      XCTAssertEqual(result, .incorrectCardAccessNumber)
      let state = await card.inspect()
      XCTAssertEqual(state.device, VirtualIDCard.DeviceState())
    }

    var state = VirtualIDCard.Scenario.activatedReader.snapshot
    state.card.readerConnected = false
    state.device.connectedCardAccessNumber = "stale"
    let card = VirtualIDCard(snapshot: state)
    let result = await card.connect(cardAccessNumber: "")
    XCTAssertEqual(result, .unavailable(.readerDisconnected))
    let disconnected = await card.inspect()
    XCTAssertNil(disconnected.device.connectedCardAccessNumber)
  }

  internal func testCredentialProbeCoversReportsAndFailures() async {
    let reporting = VirtualIDCard(scenario: .activatedReader)
    let report = await reporting.probeCredentials()
    XCTAssertEqual(
      report,
      .report(
        VirtualIDCard.RetryReport(
          pin1: RetryCount.pristineAllowance,
          pin2: RetryCount.pristineAllowance,
          puk: RetryCount.pristineAllowance)))

    let disconnected = VirtualIDCard(scenario: .activatedNearField)
    let disconnectedResult = await disconnected.probeCredentials()
    XCTAssertEqual(disconnectedResult, .unavailable(.connectionLost))

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
      XCTAssertEqual(result, .unreadable)
    }

    var state = VirtualIDCard.Scenario.activatedReader.snapshot
    state.faults = VirtualIDCard.FaultPreset.readerFailsCounterQuery.faults
    let failedReader = VirtualIDCard(snapshot: state)
    let failure = await failedReader.probeCredentials()
    XCTAssertEqual(failure, .unavailable(.readerDisconnected))
    let failedState = await failedReader.inspect()
    XCTAssertFalse(failedState.card.readerConnected)
    XCTAssertFalse(failedState.card.cardPresent)
  }

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
    XCTAssertEqual(malformedCurrent.outcome, .invalidEntry)
    let unchanged = await card.changePIN1(current: "1234", new: "1234")
    XCTAssertEqual(unchanged.outcome, .invalidEntry)
    let malformedNew = await card.changePIN2(
      current: "123456",
      new: "short")
    XCTAssertEqual(malformedNew.outcome, .invalidEntry)
    let untouched = await card.inspect()
    XCTAssertEqual(
      untouched.card.pin1.attemptsRemaining,
      RetryCount.pristineAllowance)
    XCTAssertEqual(untouched.faults.count, 1)

    let timedOut = await card.changePIN1(current: "1234", new: "9876")
    XCTAssertEqual(timedOut.outcome, .transportFailure(.timeout))
  }

  internal func testPIN2RetryFloorMatrix() async {
    for attempts in UInt8(0)...RetryCount.pristineAllowance {
      var state = VirtualIDCard.Scenario.activatedReader.snapshot
      state.card.pin2.attemptsRemaining = attempts
      let card = VirtualIDCard(snapshot: state)

      let result = await card.changePIN2(current: "000000", new: "987654")

      switch attempts {
      case 0:
        XCTAssertEqual(result.outcome, .blocked)
        XCTAssertEqual(result.snapshot.card.pin2.attemptsRemaining, 0)

      case 1...lowAttemptRefusalCeiling:
        XCTAssertEqual(result.outcome, .refusedLowAttempts(remaining: attempts))
        XCTAssertEqual(result.snapshot.card.pin2.attemptsRemaining, attempts)

      default:
        XCTAssertEqual(result.outcome, .rejected(remaining: attempts - 1))
        XCTAssertEqual(result.snapshot.card.pin2.attemptsRemaining, attempts - 1)
      }
    }
  }
}
