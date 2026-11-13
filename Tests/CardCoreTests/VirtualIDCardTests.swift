// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CardCore
import XCTest

/// Retry counts at or below this refuse without spending an attempt.
internal let lowAttemptRefusalCeiling: UInt8 = 2

internal final class VirtualIDCardTests: XCTestCase {
  internal func testWrongCardAccessNumberDoesNotConfigureDevice() async {
    let card = VirtualIDCard(scenario: .activatedNearField)

    let result = await card.connect(cardAccessNumber: "000000")
    let state = await card.inspect()

    XCTAssertEqual(result, .incorrectCardAccessNumber)
    XCTAssertNil(state.device.connectedCardAccessNumber)
    XCTAssertNil(state.device.storedCardAccessNumber)
  }

  internal func testActivatedCardStoresValidatedCardAccessNumber() async {
    let card = VirtualIDCard(scenario: .activatedNearField)

    _ = await card.connect(cardAccessNumber: "123456")
    let state = await card.inspect()

    XCTAssertEqual(state.device.storedCardAccessNumber, "123456")
  }

  internal func testConnectionClassificationDoesNotReadCertificates() async {
    var state = VirtualIDCard.Scenario.factoryFreshNearField.snapshot
    state.card.authenticationCertificate = .missing
    state.card.signatureCertificate = .unreadable
    let card = VirtualIDCard(snapshot: state)

    let result = await card.connect(cardAccessNumber: "123456")

    guard case .connected(let connected) = result else {
      XCTFail("connection classification depended on a certificate")
      return
    }
    XCTAssertTrue(connected.card.pin1.isFactoryValue)
    XCTAssertTrue(connected.card.pin2.isFactoryValue)
  }

  internal func testFactoryCardStoresCardAccessNumberWhenConnected() async {
    let card = VirtualIDCard(scenario: .factoryFreshNearField)

    _ = await card.connect(cardAccessNumber: "123456")
    let state = await card.inspect()

    XCTAssertEqual(state.device.connectedCardAccessNumber, "123456")
    XCTAssertEqual(state.device.storedCardAccessNumber, "123456")
  }

  internal func testSubsequentWrongCardAccessNumberClearsStoredCardAccessNumber() async {
    let card = VirtualIDCard(scenario: .factoryFreshNearField)

    let firstConnect = await card.connect(cardAccessNumber: "123456")
    guard case .connected = firstConnect else {
      XCTFail("initial connect failed")
      return
    }
    let connectedState = await card.inspect()
    XCTAssertEqual(connectedState.device.storedCardAccessNumber, "123456")

    let mismatchConnect = await card.connect(cardAccessNumber: "000000")
    XCTAssertEqual(mismatchConnect, .incorrectCardAccessNumber)
    let mismatchState = await card.inspect()
    XCTAssertNil(mismatchState.device.connectedCardAccessNumber)
    XCTAssertNil(mismatchState.device.storedCardAccessNumber)
  }

  internal func testActivationChangesBothFactoryCredentialsIndependently() async {
    let card = VirtualIDCard(scenario: .factoryFreshNearField)
    _ = await card.connect(cardAccessNumber: "123456")

    let result = await card.activate(
      VirtualIDCard.ActivationRequest(
        entry: "1234567",
        newPIN1: "4567",
        newPIN2: "654321"))

    XCTAssertEqual(result.pin1, .success)
    XCTAssertEqual(result.pin2, .success)
    XCTAssertFalse(result.snapshot.card.pin1.isFactoryValue)
    XCTAssertFalse(result.snapshot.card.pin2.isFactoryValue)
    XCTAssertEqual(result.snapshot.device.storedCardAccessNumber, "123456")
  }

  internal func testLostReplyAfterPIN1LeavesOnlyPIN2InFactoryState() async {
    var scenario = VirtualIDCard.Scenario.factoryFreshNearField.snapshot
    scenario.faults =
      VirtualIDCard.FaultPreset.responseLostAfterPIN1Activation.faults
    let card = VirtualIDCard(snapshot: scenario)
    _ = await card.connect(cardAccessNumber: "123456")

    let result = await card.activate(
      VirtualIDCard.ActivationRequest(
        entry: "1234567",
        newPIN1: "4567",
        newPIN2: "654321"))

    XCTAssertEqual(
      result.pin1,
      .transportFailure(.connectionLost))
    XCTAssertFalse(result.snapshot.card.pin1.isFactoryValue)
    XCTAssertTrue(result.snapshot.card.pin2.isFactoryValue)
  }

  internal func testPartialActivationContinuesWithOnlyPIN2() async {
    let card = VirtualIDCard(scenario: .partialActivationNearField)
    _ = await card.connect(cardAccessNumber: "123456")

    let result = await card.activate(
      VirtualIDCard.ActivationRequest(
        entry: "1234567",
        newPIN1: nil,
        newPIN2: "654321"))

    XCTAssertEqual(result.pin1, .alreadyActivated)
    XCTAssertEqual(result.pin2, .success)
    XCTAssertFalse(result.snapshot.card.pin1.isFactoryValue)
    XCTAssertFalse(result.snapshot.card.pin2.isFactoryValue)
    XCTAssertEqual(result.snapshot.device.storedCardAccessNumber, "123456")
  }

  internal func testNonDigitActivationEntryDoesNotSpendAttempt() async {
    let card = VirtualIDCard(scenario: .factoryFreshNearField)
    _ = await card.connect(cardAccessNumber: "123456")

    let result = await card.activate(
      VirtualIDCard.ActivationRequest(
        entry: "abcdefg",
        newPIN1: "4567",
        newPIN2: "654321"))

    XCTAssertEqual(result.pin1, .invalidEntry)
    XCTAssertEqual(
      result.snapshot.card.pin1.attemptsRemaining,
      RetryCount.pristineAllowance)
  }

  internal func testWrongPINDecrementsOnlyItsOwnCounter() async {
    let card = VirtualIDCard(scenario: .activatedNearField)
    _ = await card.connect(cardAccessNumber: "123456")

    let result = await card.changePIN1(current: "0000", new: "9876")

    XCTAssertEqual(result.outcome, .rejected(remaining: 4))
    XCTAssertEqual(result.snapshot.card.pin1.attemptsRemaining, 4)
    XCTAssertEqual(
      result.snapshot.card.pin2.attemptsRemaining,
      RetryCount.pristineAllowance)
  }

  internal func testLastTwoAttemptsAreNeverSpent() async {
    let card = VirtualIDCard(scenario: .pin1RecoveryReader)

    let result = await card.changePIN1(current: "0000", new: "9876")

    XCTAssertEqual(result.outcome, .refusedLowAttempts(remaining: 2))
    XCTAssertEqual(result.snapshot.card.pin1.attemptsRemaining, 2)
  }

  internal func testPIN1RetryFloorMatrix() async {
    for attempts in UInt8(0)...RetryCount.pristineAllowance {
      var state = VirtualIDCard.Scenario.activatedReader.snapshot
      state.card.pin1.attemptsRemaining = attempts
      let card = VirtualIDCard(snapshot: state)

      let result = await card.changePIN1(current: "0000", new: "9876")

      switch attempts {
      case 0:
        XCTAssertEqual(result.outcome, .blocked)
        XCTAssertEqual(result.snapshot.card.pin1.attemptsRemaining, 0)

      case 1...lowAttemptRefusalCeiling:
        XCTAssertEqual(
          result.outcome,
          .refusedLowAttempts(remaining: attempts))
        XCTAssertEqual(
          result.snapshot.card.pin1.attemptsRemaining,
          attempts)

      default:
        XCTAssertEqual(
          result.outcome,
          .rejected(remaining: attempts - 1))
        XCTAssertEqual(
          result.snapshot.card.pin1.attemptsRemaining,
          attempts - 1)
      }
    }
  }

  internal func testSafePUKCanResetBlockedPIN() async {
    var state = VirtualIDCard.Scenario.activatedReader.snapshot
    state.card.pin1.attemptsRemaining = 0
    let card = VirtualIDCard(snapshot: state)

    let result = await card.resetPIN1(puk: "12345678", new: "9876")

    XCTAssertEqual(result.outcome, .success)
    XCTAssertEqual(
      result.snapshot.card.pin1.attemptsRemaining,
      RetryCount.pristineAllowance)
    XCTAssertEqual(result.snapshot.card.pin1.value, "9876")
  }

  internal func testPUKFloorRefusesResetWithoutChangingCard() async {
    let card = VirtualIDCard(scenario: .pukRecoveryRefusedReader)

    let result = await card.resetPIN1(puk: "12345678", new: "9876")

    XCTAssertEqual(result.outcome, .refusedLowAttempts(remaining: 2))
    XCTAssertEqual(result.snapshot.card.pin1.attemptsRemaining, 0)
    XCTAssertEqual(result.snapshot.card.puk.attemptsRemaining, 2)
  }

  internal func testFaultBeforeCommandDoesNotMutateCredential() async {
    var state = VirtualIDCard.Scenario.activatedReader.snapshot
    state.faults =
      VirtualIDCard.FaultPreset.cardRemovedDuringPINChange.faults
    let card = VirtualIDCard(snapshot: state)

    let result = await card.changePIN1(current: "1234", new: "9876")

    XCTAssertEqual(result.outcome, .transportFailure(.cardRemoved))
    XCTAssertEqual(result.snapshot.card.pin1.value, "1234")
    XCTAssertFalse(result.snapshot.card.cardPresent)
  }

  internal func testFaultAfterCommandPreservesCardMutation() async {
    var state = VirtualIDCard.Scenario.activatedReader.snapshot
    state.faults = [
      VirtualIDCard.Fault(
        operation: .changePIN1,
        phase: .afterCardExecution,
        effect: .timeout)
    ]
    let card = VirtualIDCard(snapshot: state)

    let result = await card.changePIN1(current: "1234", new: "9876")

    XCTAssertEqual(result.outcome, .transportFailure(.timeout))
    XCTAssertEqual(result.snapshot.card.pin1.value, "9876")
    XCTAssertEqual(
      result.snapshot.card.pin1.attemptsRemaining,
      RetryCount.pristineAllowance)
  }
}
