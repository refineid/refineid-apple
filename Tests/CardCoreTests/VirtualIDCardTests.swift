// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CardCore
import Testing

/// Retry counts at or below this refuse without spending an attempt.
internal let lowAttemptRefusalCeiling: UInt8 = RetryCount.lowAttemptCeiling

@Suite(.serialized)
internal final class VirtualIDCardTests {
  @Test
  internal func testWrongCardAccessNumberDoesNotConfigureDevice() async {
    let card = VirtualIDCard(scenario: .activatedNearField)

    let result = await card.connect(cardAccessNumber: "000000")
    let state = await card.inspect()

    expectState(result == .incorrectCardAccessNumber, sourceLocation: #_sourceLocation)
    expectState(state.device.connectedCardAccessNumber == nil, sourceLocation: #_sourceLocation)
    expectState(state.device.storedCardAccessNumber == nil, sourceLocation: #_sourceLocation)
  }

  @Test
  internal func testActivatedCardStoresValidatedCardAccessNumber() async {
    let card = VirtualIDCard(scenario: .activatedNearField)
    let expectedAccessNumber = (await card.inspect()).card.cardAccessNumber

    _ = await card.connect(cardAccessNumber: "123456")
    let state = await card.inspect()

    expectState(
      state.device.storedCardAccessNumber == expectedAccessNumber, sourceLocation: #_sourceLocation)
  }

  @Test
  internal func testConnectionClassificationDoesNotReadCertificates() async {
    var state = VirtualIDCard.Scenario.factoryFreshNearField.snapshot
    state.card.authenticationCertificate = .missing
    state.card.signatureCertificate = .unreadable
    let card = VirtualIDCard(snapshot: state)

    let result = await card.connect(cardAccessNumber: "123456")

    guard case .connected(let connected) = result else {
      Issue.record("connection classification depended on a certificate")
      return
    }
    #expect(connected.card.pin1.isFactoryValue, sourceLocation: #_sourceLocation)
    #expect(connected.card.pin2.isFactoryValue, sourceLocation: #_sourceLocation)
  }

  @Test
  internal func testFactoryCardStoresCardAccessNumberWhenConnected() async {
    let card = VirtualIDCard(scenario: .factoryFreshNearField)
    let expectedAccessNumber = (await card.inspect()).card.cardAccessNumber

    _ = await card.connect(cardAccessNumber: "123456")
    let state = await card.inspect()

    expectState(
      state.device.connectedCardAccessNumber == expectedAccessNumber,
      sourceLocation: #_sourceLocation)
    expectState(
      state.device.storedCardAccessNumber == expectedAccessNumber, sourceLocation: #_sourceLocation)
  }

  @Test
  internal func testSubsequentWrongCardAccessNumberClearsStoredCardAccessNumber() async {
    let card = VirtualIDCard(scenario: .factoryFreshNearField)
    let expectedAccessNumber = (await card.inspect()).card.cardAccessNumber

    let firstConnect = await card.connect(cardAccessNumber: "123456")
    guard case .connected = firstConnect else {
      Issue.record("initial connect failed")
      return
    }
    let connectedState = await card.inspect()
    expectState(
      connectedState.device.storedCardAccessNumber == expectedAccessNumber,
      sourceLocation: #_sourceLocation)

    let mismatchConnect = await card.connect(cardAccessNumber: "000000")
    expectState(mismatchConnect == .incorrectCardAccessNumber, sourceLocation: #_sourceLocation)
    let mismatchState = await card.inspect()
    expectState(
      mismatchState.device.connectedCardAccessNumber == nil, sourceLocation: #_sourceLocation)
    expectState(
      mismatchState.device.storedCardAccessNumber == nil, sourceLocation: #_sourceLocation)
  }

  @Test
  internal func testActivationChangesBothFactoryCredentialsIndependently() async {
    let card = VirtualIDCard(scenario: .factoryFreshNearField)
    let expectedAccessNumber = (await card.inspect()).card.cardAccessNumber
    _ = await card.connect(cardAccessNumber: "123456")

    let result = await card.activate(
      VirtualIDCard.ActivationRequest(
        entry: "1234567",
        newPIN1: "4567",
        newPIN2: "654321"))

    expectState(result.pin1 == .success, sourceLocation: #_sourceLocation)
    expectState(result.pin2 == .success, sourceLocation: #_sourceLocation)
    #expect(!result.snapshot.card.pin1.isFactoryValue, sourceLocation: #_sourceLocation)
    #expect(!result.snapshot.card.pin2.isFactoryValue, sourceLocation: #_sourceLocation)
    expectState(
      result.snapshot.device.storedCardAccessNumber == expectedAccessNumber,
      sourceLocation: #_sourceLocation)
  }

  @Test
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

    expectState(
      result.pin1 == (.transportFailure(.connectionLost)), sourceLocation: #_sourceLocation)
    #expect(!result.snapshot.card.pin1.isFactoryValue, sourceLocation: #_sourceLocation)
    #expect(result.snapshot.card.pin2.isFactoryValue, sourceLocation: #_sourceLocation)
  }

  @Test
  internal func testPartialActivationContinuesWithOnlyPIN2() async {
    let card = VirtualIDCard(scenario: .partialActivationNearField)
    let expectedAccessNumber = (await card.inspect()).card.cardAccessNumber
    _ = await card.connect(cardAccessNumber: "123456")

    let result = await card.activate(
      VirtualIDCard.ActivationRequest(
        entry: "1234567",
        newPIN1: nil,
        newPIN2: "654321"))

    expectState(result.pin1 == .alreadyActivated, sourceLocation: #_sourceLocation)
    expectState(result.pin2 == .success, sourceLocation: #_sourceLocation)
    #expect(!result.snapshot.card.pin1.isFactoryValue, sourceLocation: #_sourceLocation)
    #expect(!result.snapshot.card.pin2.isFactoryValue, sourceLocation: #_sourceLocation)
    expectState(
      result.snapshot.device.storedCardAccessNumber == expectedAccessNumber,
      sourceLocation: #_sourceLocation)
  }

  @Test
  internal func testNonDigitActivationEntryDoesNotSpendAttempt() async {
    let card = VirtualIDCard(scenario: .factoryFreshNearField)
    _ = await card.connect(cardAccessNumber: "123456")

    let result = await card.activate(
      VirtualIDCard.ActivationRequest(
        entry: "abcdefg",
        newPIN1: "4567",
        newPIN2: "654321"))

    expectState(result.pin1 == .invalidEntry, sourceLocation: #_sourceLocation)
    #expect(
      result.snapshot.card.pin1.attemptsRemaining == RetryCount.pristineAllowance,
      sourceLocation: #_sourceLocation)
  }

  @Test
  internal func testWrongPINDecrementsOnlyItsOwnCounter() async {
    let card = VirtualIDCard(scenario: .activatedNearField)
    _ = await card.connect(cardAccessNumber: "123456")

    let result = await card.changePIN1(current: "0000", new: "9876")

    #expect(result.outcome == (.rejected(remaining: 4)), sourceLocation: #_sourceLocation)
    #expect(result.snapshot.card.pin1.attemptsRemaining == 4, sourceLocation: #_sourceLocation)
    #expect(
      result.snapshot.card.pin2.attemptsRemaining == RetryCount.pristineAllowance,
      sourceLocation: #_sourceLocation)
  }

  @Test
  internal func testLastAttemptIsNeverSpent() async {
    let card = VirtualIDCard(scenario: .pin1RecoveryReader)

    let result = await card.changePIN1(current: "0000", new: "9876")

    #expect(
      result.outcome == (.refusedLowAttempts(remaining: RetryCount.lowAttemptCeiling)),
      sourceLocation: #_sourceLocation)
    #expect(
      result.snapshot.card.pin1.attemptsRemaining == RetryCount.lowAttemptCeiling,
      sourceLocation: #_sourceLocation)
  }

  @Test
  internal func testPIN1RetryFloorMatrix() async {
    for attempts in UInt8(0)...RetryCount.pristineAllowance {
      var state = VirtualIDCard.Scenario.activatedReader.snapshot
      state.card.pin1.attemptsRemaining = attempts
      let card = VirtualIDCard(snapshot: state)

      let result = await card.changePIN1(current: "0000", new: "9876")

      switch attempts {
      case 0:
        #expect(result.outcome == .blocked, sourceLocation: #_sourceLocation)
        #expect(result.snapshot.card.pin1.attemptsRemaining == 0, sourceLocation: #_sourceLocation)

      case 1...lowAttemptRefusalCeiling:
        #expect(
          result.outcome == (.refusedLowAttempts(remaining: attempts)),
          sourceLocation: #_sourceLocation)
        #expect(
          result.snapshot.card.pin1.attemptsRemaining == attempts, sourceLocation: #_sourceLocation)

      default:
        #expect(
          result.outcome == (.rejected(remaining: attempts - 1)), sourceLocation: #_sourceLocation)
        #expect(
          result.snapshot.card.pin1.attemptsRemaining == (attempts - 1),
          sourceLocation: #_sourceLocation)
      }
    }
  }

  @Test
  internal func testSafePUKCanResetBlockedPIN() async throws {
    var state = VirtualIDCard.Scenario.activatedReader.snapshot
    state.card.pin1.attemptsRemaining = 0
    let replacementEntry = try Self.changedPin1(from: state.card.pin1.value)
    let card = VirtualIDCard(snapshot: state)

    let result = await card.resetPIN1(puk: state.card.puk.value, new: replacementEntry)

    #expect(result.outcome == .success, sourceLocation: #_sourceLocation)
    #expect(
      result.snapshot.card.pin1.attemptsRemaining == RetryCount.pristineAllowance,
      sourceLocation: #_sourceLocation)
    expectState(
      result.snapshot.card.pin1.value == replacementEntry, sourceLocation: #_sourceLocation)
  }

  @Test
  internal func testPUKFloorRefusesResetWithoutChangingCard() async {
    let card = VirtualIDCard(scenario: .pukRecoveryRefusedReader)

    let result = await card.resetPIN1(puk: "12345678", new: "9876")

    #expect(
      result.outcome == (.refusedLowAttempts(remaining: RetryCount.lowAttemptCeiling)),
      sourceLocation: #_sourceLocation)
    #expect(result.snapshot.card.pin1.attemptsRemaining == 0, sourceLocation: #_sourceLocation)
    #expect(
      result.snapshot.card.puk.attemptsRemaining == RetryCount.lowAttemptCeiling,
      sourceLocation: #_sourceLocation)
  }

  @Test
  internal func testFaultBeforeCommandDoesNotMutateCredential() async throws {
    var state = VirtualIDCard.Scenario.activatedReader.snapshot
    state.faults =
      VirtualIDCard.FaultPreset.cardRemovedDuringPINChange.faults
    let replacementEntry = try Self.changedPin1(from: state.card.pin1.value)
    let card = VirtualIDCard(snapshot: state)

    let result = await card.changePIN1(current: state.card.pin1.value, new: replacementEntry)

    #expect(result.outcome == (.transportFailure(.cardRemoved)), sourceLocation: #_sourceLocation)
    expectState(
      result.snapshot.card.pin1.value == state.card.pin1.value, sourceLocation: #_sourceLocation)
    #expect(!result.snapshot.card.cardPresent, sourceLocation: #_sourceLocation)
  }

  @Test
  internal func testFaultAfterCommandPreservesCardMutation() async throws {
    var state = VirtualIDCard.Scenario.activatedReader.snapshot
    state.faults = [
      VirtualIDCard.Fault(
        operation: .changePIN1,
        phase: .afterCardExecution,
        effect: .timeout)
    ]
    let replacementEntry = try Self.changedPin1(from: state.card.pin1.value)
    let card = VirtualIDCard(snapshot: state)

    let result = await card.changePIN1(current: state.card.pin1.value, new: replacementEntry)

    #expect(result.outcome == (.transportFailure(.timeout)), sourceLocation: #_sourceLocation)
    expectState(
      result.snapshot.card.pin1.value == replacementEntry, sourceLocation: #_sourceLocation)
    #expect(
      result.snapshot.card.pin1.attemptsRemaining == RetryCount.pristineAllowance,
      sourceLocation: #_sourceLocation)
  }
}
