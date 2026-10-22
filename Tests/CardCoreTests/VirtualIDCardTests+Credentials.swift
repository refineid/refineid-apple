// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CardCore
import XCTest

extension VirtualIDCardTests {
  internal func testPUKRetryFloorMatrix() async {
    for attempts in UInt8(0)...RetryCount.pristineAllowance {
      var state = VirtualIDCard.Scenario.activatedReader.snapshot
      state.card.pin1.attemptsRemaining = 0
      state.card.puk.attemptsRemaining = attempts
      let card = VirtualIDCard(snapshot: state)

      let result = await card.resetPIN1(puk: "00000000", new: "9876")

      switch attempts {
      case 0:
        XCTAssertEqual(result.outcome, .blocked)
        XCTAssertEqual(result.snapshot.card.puk.attemptsRemaining, 0)

      case 1...lowAttemptRefusalCeiling:
        XCTAssertEqual(result.outcome, .refusedLowAttempts(remaining: attempts))
        XCTAssertEqual(result.snapshot.card.puk.attemptsRemaining, attempts)

      default:
        XCTAssertEqual(result.outcome, .rejected(remaining: attempts - 1))
        XCTAssertEqual(result.snapshot.card.puk.attemptsRemaining, attempts - 1)
      }
      XCTAssertEqual(result.snapshot.card.pin1.attemptsRemaining, 0)
    }
  }

  internal func testPIN2ChangeAndResetUseTheSameSafetyRules() async {
    let changing = VirtualIDCard(scenario: .activatedReader)
    let changed = await changing.changePIN2(current: "123456", new: "987654")
    XCTAssertEqual(changed.outcome, .success)
    XCTAssertEqual(changed.snapshot.card.pin2.value, "987654")

    var state = VirtualIDCard.Scenario.activatedReader.snapshot
    state.card.pin2.attemptsRemaining = 0
    let resetting = VirtualIDCard(snapshot: state)
    let reset = await resetting.resetPIN2(puk: "12345678", new: "987654")
    XCTAssertEqual(reset.outcome, .success)
    XCTAssertEqual(reset.snapshot.card.pin2.value, "987654")
    XCTAssertEqual(
      reset.snapshot.card.pin2.attemptsRemaining,
      RetryCount.pristineAllowance)
  }

  internal func testMalformedResetInputDoesNotSpendPUK() async {
    for input in [
      (puk: "123", pin: "9876"),
      (puk: "notdigits", pin: "9876"),
      (puk: "12345678", pin: "12"),
    ] {
      let card = VirtualIDCard(scenario: .activatedReader)
      let result = await card.resetPIN1(puk: input.puk, new: input.pin)
      XCTAssertEqual(result.outcome, .invalidEntry)
      XCTAssertEqual(
        result.snapshot.card.puk.attemptsRemaining,
        RetryCount.pristineAllowance)
    }
  }

  internal func testActivationValidationAndAlreadyActivatedResult() async {
    let activated = VirtualIDCard(scenario: .activatedNearField)
    let alreadyActivated = await activated.activate(
      VirtualIDCard.ActivationRequest(
        entry: "1234567",
        newPIN1: "4567",
        newPIN2: "654321"))
    XCTAssertEqual(alreadyActivated.pin1, .alreadyActivated)

    let factory = VirtualIDCard(scenario: .factoryFreshNearField)
    _ = await factory.connect(cardAccessNumber: "123456")
    let missingPIN1 = await factory.activate(
      VirtualIDCard.ActivationRequest(
        entry: "1234567",
        newPIN1: nil,
        newPIN2: "654321"))
    XCTAssertEqual(missingPIN1.pin1, .invalidEntry)

    let partial = VirtualIDCard(scenario: .partialActivationNearField)
    _ = await partial.connect(cardAccessNumber: "123456")
    let missingPIN2 = await partial.activate(
      VirtualIDCard.ActivationRequest(
        entry: "1234567",
        newPIN1: nil,
        newPIN2: nil))
    XCTAssertEqual(missingPIN2.pin1, .alreadyActivated)
    XCTAssertEqual(missingPIN2.pin2, .invalidEntry)

    let legacy = VirtualIDCard(scenario: .legacyFactoryFreshNearField)
    _ = await legacy.connect(cardAccessNumber: "123456")
    let wrongLength = await legacy.activate(
      VirtualIDCard.ActivationRequest(
        entry: "1234567",
        newPIN1: "4567",
        newPIN2: "654321"))
    XCTAssertEqual(wrongLength.pin1, .invalidEntry)
    XCTAssertEqual(
      wrongLength.snapshot.card.puk.attemptsRemaining,
      RetryCount.pristineAllowance)
  }

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

    XCTAssertEqual(result.pin1, .success)
    XCTAssertEqual(result.pin2, .success)
    XCTAssertFalse(result.snapshot.card.pin1.isFactoryValue)
    XCTAssertFalse(result.snapshot.card.pin2.isFactoryValue)
    XCTAssertEqual(
      result.snapshot.card.puk.attemptsRemaining,
      RetryCount.pristineAllowance)
  }

  internal func testLostFinalActivationReplyRequiresSuccessfulReconnectBeforeCANStorage() async {
    var state = VirtualIDCard.Scenario.factoryFreshNearField.snapshot
    state.faults = VirtualIDCard.FaultPreset.responseLostAfterPIN2Activation.faults
    let card = VirtualIDCard(snapshot: state)
    _ = await card.connect(cardAccessNumber: "123456")

    let result = await card.activate(
      VirtualIDCard.ActivationRequest(
        entry: "1234567",
        newPIN1: "4567",
        newPIN2: "654321"))

    XCTAssertEqual(result.pin1, .success)
    XCTAssertEqual(result.pin2, .transportFailure(.connectionLost))
    XCTAssertFalse(result.snapshot.card.pin1.isFactoryValue)
    XCTAssertFalse(result.snapshot.card.pin2.isFactoryValue)
    XCTAssertNil(result.snapshot.device.storedCardAccessNumber)

    _ = await card.connect(cardAccessNumber: "123456")
    let reconnected = await card.inspect()
    XCTAssertEqual(reconnected.device.storedCardAccessNumber, "123456")
  }

  internal func testRegistrationCertificateAndPublicationFailures() async {
    for certificate in VirtualIDCard.CertificateState.allCases
    where certificate != .valid {
      var state = VirtualIDCard.Scenario.activatedReader.snapshot
      state.card.authenticationCertificate = certificate
      let card = VirtualIDCard(snapshot: state)
      let result = await card.register()
      XCTAssertEqual(
        result,
        .certificateUnavailable,
        "\(certificate.rawValue) certificate was accepted")
    }

    var state = VirtualIDCard.Scenario.activatedReader.snapshot
    state.card.signatureCertificate = .revoked
    state.faults = VirtualIDCard.FaultPreset.tokenPublicationFailure.faults
    let publication = VirtualIDCard(snapshot: state)
    guard
      case .tokenPublicationFailed(let failed) =
        await publication.register()
    else {
      XCTFail("token publication fault was not surfaced")
      return
    }
    XCTAssertTrue(failed.device.cachedIdentity)
    XCTAssertFalse(failed.device.tokenRegistered)

    state = VirtualIDCard.Scenario.activatedReader.snapshot
    state.faults = [
      VirtualIDCard.Fault(
        operation: .register,
        phase: .afterCardExecution,
        effect: .timeout)
    ]
    let lostReply = VirtualIDCard(snapshot: state)
    let lostResult = await lostReply.register()
    XCTAssertEqual(lostResult, .transportFailure(.timeout))
    let lostState = await lostReply.inspect()
    XCTAssertEqual(
      lostState.card.pin1.attemptsRemaining,
      RetryCount.pristineAllowance)
  }

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
    XCTAssertEqual(first, .unavailable(.timeout))
    let onceRemaining = await card.inspect()
    XCTAssertEqual(onceRemaining.faults.first?.remainingOccurrences, 1)
    let second = await card.connect(cardAccessNumber: "123456")
    XCTAssertEqual(second, .unavailable(.timeout))
    let consumed = await card.inspect()
    XCTAssertTrue(consumed.faults.isEmpty)
    guard case .connected = await card.connect(cardAccessNumber: "123456") else {
      XCTFail("consumed wildcard fault remained active")
      return
    }
  }
}
