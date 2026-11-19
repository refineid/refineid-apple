// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CardCore
import Testing

extension VirtualIDCardTests {
  @Test
  internal func testPUKRetryFloorMatrix() async {
    for attempts in UInt8(0)...RetryCount.pristineAllowance {
      var state = VirtualIDCard.Scenario.activatedReader.snapshot
      state.card.pin1.attemptsRemaining = 0
      state.card.puk.attemptsRemaining = attempts
      let card = VirtualIDCard(snapshot: state)

      let result = await card.resetPIN1(puk: "00000000", new: "9876")

      switch attempts {
      case 0:
        // The PUK goes to the card, which answers blocked and spends
        // nothing.
        #expect(result.outcome == .blocked, sourceLocation: #_sourceLocation)
        #expect(result.snapshot.card.puk.attemptsRemaining == 0, sourceLocation: #_sourceLocation)

      case 1...lowAttemptRefusalCeiling:
        #expect(
          result.outcome == (.refusedLowAttempts(remaining: attempts)),
          sourceLocation: #_sourceLocation)
        #expect(
          result.snapshot.card.puk.attemptsRemaining == attempts, sourceLocation: #_sourceLocation)

      default:
        #expect(
          result.outcome == (.rejected(remaining: attempts - 1)), sourceLocation: #_sourceLocation)
        #expect(
          result.snapshot.card.puk.attemptsRemaining == (attempts - 1),
          sourceLocation: #_sourceLocation)
      }
      #expect(result.snapshot.card.pin1.attemptsRemaining == 0, sourceLocation: #_sourceLocation)
    }
  }

  @Test
  internal func testCorrectPUKAtNoTriesLeftIsAnsweredBlockedByTheCard() async {
    var state = VirtualIDCard.Scenario.activatedReader.snapshot
    state.card.pin1.attemptsRemaining = 0
    state.card.puk.attemptsRemaining = 0
    let card = VirtualIDCard(snapshot: state)

    let result = await card.resetPIN1(puk: state.card.puk.value, new: "9876")

    #expect(result.outcome == .blocked, sourceLocation: #_sourceLocation)
    #expect(result.snapshot.card.puk.attemptsRemaining == 0, sourceLocation: #_sourceLocation)
    #expect(result.snapshot.card.pin1.attemptsRemaining == 0, sourceLocation: #_sourceLocation)
  }

  @Test
  internal func testCorrectPINAtNoTriesLeftIsAnsweredBlockedByTheCard() async {
    var state = VirtualIDCard.Scenario.activatedReader.snapshot
    state.card.pin1.attemptsRemaining = 0
    let card = VirtualIDCard(snapshot: state)

    let result = await card.changePIN1(current: state.card.pin1.value, new: "9876")

    #expect(result.outcome == .blocked, sourceLocation: #_sourceLocation)
    #expect(result.snapshot.card.pin1.attemptsRemaining == 0, sourceLocation: #_sourceLocation)
  }

  @Test
  internal func testPIN2ChangeAndResetUseTheSameSafetyRules() async throws {
    let changing = VirtualIDCard(scenario: .activatedReader)
    let initialChangingState = await changing.inspect()
    let changedEntry = try Self.changedPin2(from: initialChangingState.card.pin2.value)
    let changed = await changing.changePIN2(
      current: initialChangingState.card.pin2.value, new: changedEntry)
    #expect(changed.outcome == .success, sourceLocation: #_sourceLocation)
    expectState(changed.snapshot.card.pin2.value == changedEntry, sourceLocation: #_sourceLocation)

    var state = VirtualIDCard.Scenario.activatedReader.snapshot
    state.card.pin2.attemptsRemaining = 0
    let resetEntry = try Self.changedPin2(from: state.card.pin2.value)
    let resetting = VirtualIDCard(snapshot: state)
    let reset = await resetting.resetPIN2(puk: state.card.puk.value, new: resetEntry)
    #expect(reset.outcome == .success, sourceLocation: #_sourceLocation)
    expectState(reset.snapshot.card.pin2.value == resetEntry, sourceLocation: #_sourceLocation)
    #expect(
      reset.snapshot.card.pin2.attemptsRemaining == RetryCount.pristineAllowance,
      sourceLocation: #_sourceLocation)
  }

  @Test
  internal func testMalformedResetInputDoesNotSpendPUK() async {
    for input in [
      (puk: "123", pin: "9876"),
      (puk: "notdigits", pin: "9876"),
      (puk: "12345678", pin: "12"),
    ] {
      let card = VirtualIDCard(scenario: .activatedReader)
      let result = await card.resetPIN1(puk: input.puk, new: input.pin)
      #expect(result.outcome == .invalidEntry, sourceLocation: #_sourceLocation)
      #expect(
        result.snapshot.card.puk.attemptsRemaining == RetryCount.pristineAllowance,
        sourceLocation: #_sourceLocation)
    }
  }

  @Test
  internal func testActivationValidationAndAlreadyActivatedResult() async {
    let activated = VirtualIDCard(scenario: .activatedNearField)
    let alreadyActivated = await activated.activate(
      VirtualIDCard.ActivationRequest(
        entry: "1234567",
        newPIN1: "4567",
        newPIN2: "654321"))
    expectState(alreadyActivated.pin1 == .alreadyActivated, sourceLocation: #_sourceLocation)

    let factory = VirtualIDCard(scenario: .factoryFreshNearField)
    _ = await factory.connect(cardAccessNumber: "123456")
    let missingPIN1 = await factory.activate(
      VirtualIDCard.ActivationRequest(
        entry: "1234567",
        newPIN1: nil,
        newPIN2: "654321"))
    expectState(missingPIN1.pin1 == .invalidEntry, sourceLocation: #_sourceLocation)

    let partial = VirtualIDCard(scenario: .partialActivationNearField)
    _ = await partial.connect(cardAccessNumber: "123456")
    let missingPIN2 = await partial.activate(
      VirtualIDCard.ActivationRequest(
        entry: "1234567",
        newPIN1: nil,
        newPIN2: nil))
    expectState(missingPIN2.pin1 == .alreadyActivated, sourceLocation: #_sourceLocation)
    expectState(missingPIN2.pin2 == .invalidEntry, sourceLocation: #_sourceLocation)

    let legacy = VirtualIDCard(scenario: .legacyFactoryFreshNearField)
    _ = await legacy.connect(cardAccessNumber: "123456")
    let wrongLength = await legacy.activate(
      VirtualIDCard.ActivationRequest(
        entry: "1234567",
        newPIN1: "4567",
        newPIN2: "654321"))
    expectState(wrongLength.pin1 == .invalidEntry, sourceLocation: #_sourceLocation)
    #expect(
      wrongLength.snapshot.card.puk.attemptsRemaining == RetryCount.pristineAllowance,
      sourceLocation: #_sourceLocation)
  }

  @Test
  internal func testLegacyActivationUsesPUKWithoutCertificateReads() async {
    var state = VirtualIDCard.Scenario.legacyFactoryFreshNearField.snapshot
    state.card.authenticationCertificate = .unreadable
    state.card.signatureCertificate = .missing
    let card = VirtualIDCard(snapshot: state)
    _ = await card.connect(cardAccessNumber: "123456")

    let result = await card.activate(
      VirtualIDCard.ActivationRequest(
        entry: "12345678",
        newPIN1: "4567",
        newPIN2: "654321"))

    expectState(result.pin1 == .success, sourceLocation: #_sourceLocation)
    expectState(result.pin2 == .success, sourceLocation: #_sourceLocation)
    #expect(!result.snapshot.card.pin1.isFactoryValue, sourceLocation: #_sourceLocation)
    #expect(!result.snapshot.card.pin2.isFactoryValue, sourceLocation: #_sourceLocation)
    #expect(
      result.snapshot.card.puk.attemptsRemaining == RetryCount.pristineAllowance,
      sourceLocation: #_sourceLocation)
  }

  @Test
  internal func testLostFinalActivationReplyRetainsProvenCANForReconnect() async {
    var state = VirtualIDCard.Scenario.factoryFreshNearField.snapshot
    state.faults = VirtualIDCard.FaultPreset.responseLostAfterPIN2Activation.faults
    let card = VirtualIDCard(snapshot: state)
    let expectedAccessNumber = (await card.inspect()).card.cardAccessNumber
    _ = await card.connect(cardAccessNumber: "123456")

    let result = await card.activate(
      VirtualIDCard.ActivationRequest(
        entry: "1234567",
        newPIN1: "4567",
        newPIN2: "654321"))

    expectState(result.pin1 == .success, sourceLocation: #_sourceLocation)
    expectState(
      result.pin2 == (.transportFailure(.connectionLost)), sourceLocation: #_sourceLocation)
    #expect(!result.snapshot.card.pin1.isFactoryValue, sourceLocation: #_sourceLocation)
    #expect(!result.snapshot.card.pin2.isFactoryValue, sourceLocation: #_sourceLocation)
    expectState(
      result.snapshot.device.storedCardAccessNumber == expectedAccessNumber,
      sourceLocation: #_sourceLocation)

    _ = await card.connect(cardAccessNumber: "123456")
    let reconnected = await card.inspect()
    expectState(
      reconnected.device.storedCardAccessNumber == expectedAccessNumber,
      sourceLocation: #_sourceLocation)
  }

  @Test
  internal func testRegistrationCertificateAndPublicationFailures() async {
    for certificate in VirtualIDCard.CertificateState.allCases
    where certificate != .valid {
      var state = VirtualIDCard.Scenario.activatedReader.snapshot
      state.card.authenticationCertificate = certificate
      let card = VirtualIDCard(snapshot: state)
      let result = await card.register()
      expectState(result == .certificateUnavailable, sourceLocation: #_sourceLocation)
    }

    var state = VirtualIDCard.Scenario.activatedReader.snapshot
    state.card.signatureCertificate = .revoked
    state.faults = VirtualIDCard.FaultPreset.tokenPublicationFailure.faults
    let publication = VirtualIDCard(snapshot: state)
    guard
      case .tokenPublicationFailed(let failed) =
        await publication.register()
    else {
      Issue.record("token publication fault was not surfaced")
      return
    }
    expectState(failed.device.cachedIdentity, sourceLocation: #_sourceLocation)
    expectState(!failed.device.tokenRegistered, sourceLocation: #_sourceLocation)

    state = VirtualIDCard.Scenario.activatedReader.snapshot
    state.faults = [
      VirtualIDCard.Fault(
        operation: .register,
        phase: .afterCardExecution,
        effect: .timeout)
    ]
    let lostReply = VirtualIDCard(snapshot: state)
    let lostResult = await lostReply.register()
    expectState(lostResult == (.transportFailure(.timeout)), sourceLocation: #_sourceLocation)
    let lostState = await lostReply.inspect()
    #expect(
      lostState.card.pin1.attemptsRemaining == RetryCount.pristineAllowance,
      sourceLocation: #_sourceLocation)
  }

  @Test
  internal func testWildcardFaultRepeatsExactlyAsConfigured() async {
    let card = VirtualIDCard(scenario: .activatedNearField)
    let configuredOccurrences = 2
    await card.enqueue(
      VirtualIDCard.Fault(
        operation: .any,
        phase: .beforeCommand,
        effect: .timeout,
        remainingOccurrences: configuredOccurrences))

    let first = await card.connect(cardAccessNumber: "123456")
    expectState(first == (.unavailable(.timeout)), sourceLocation: #_sourceLocation)
    let onceRemaining = await card.inspect()
    expectState(
      (onceRemaining.faults.first?.remainingOccurrences) == 1, sourceLocation: #_sourceLocation)
    let second = await card.connect(cardAccessNumber: "123456")
    expectState(second == (.unavailable(.timeout)), sourceLocation: #_sourceLocation)
    let consumed = await card.inspect()
    expectState(consumed.faults.isEmpty, sourceLocation: #_sourceLocation)
    guard case .connected = await card.connect(cardAccessNumber: "123456") else {
      Issue.record("consumed wildcard fault remained active")
      return
    }
  }
}
