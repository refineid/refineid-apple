// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CardCore
import XCTest

internal final class VirtualIDCardSigningTests: XCTestCase {
  internal func testQualifiedSignatureSuccessRestoresPIN2Allowance() async {
    var state = VirtualIDCard.Scenario.registeredNearField.snapshot
    state.card.pin2.attemptsRemaining = 3
    let card = VirtualIDCard(snapshot: state)

    let result = await card.authorizeQualifiedSignature(
      pin2: state.card.pin2.value)
    let latest = await card.inspect()

    XCTAssertEqual(result, .success)
    XCTAssertEqual(latest.card.pin2.attemptsRemaining, 5)
    XCTAssertFalse(latest.device.pendingSigningRequest)
  }

  internal func testInvalidSignatureEntriesNeverReachTheCard() async {
    let invalid = ["", "123", "1234567890123", "12a456"]
    for entry in invalid {
      var state = VirtualIDCard.Scenario.registeredNearField.snapshot
      state.card.pin2.attemptsRemaining = 4
      let card = VirtualIDCard(snapshot: state)

      let result = await card.authorizeQualifiedSignature(pin2: entry)
      XCTAssertEqual(result, .invalidEntry)
      let latest = await card.inspect()
      XCTAssertEqual(latest.card.pin2.attemptsRemaining, 4)
      XCTAssertFalse(latest.device.pendingSigningRequest)
    }
  }

  internal func testQualifiedSignatureNeverSpendsLastTwoAttempts() async {
    for remaining: UInt8 in 0...2 {
      var state = VirtualIDCard.Scenario.registeredNearField.snapshot
      state.card.pin2.attemptsRemaining = remaining
      let card = VirtualIDCard(snapshot: state)

      let result = await card.authorizeQualifiedSignature(pin2: "000000")
      let latest = await card.inspect()

      if remaining == 0 {
        XCTAssertEqual(result, .blocked)
      } else {
        XCTAssertEqual(
          result,
          .refusedLowAttempts(remaining: remaining))
      }
      XCTAssertEqual(latest.card.pin2.attemptsRemaining, remaining)
    }
  }

  internal func testWrongSignaturePINConsumesExactlyOneEligibleAttempt() async {
    for remaining: UInt8 in 3...5 {
      var state = VirtualIDCard.Scenario.registeredNearField.snapshot
      state.card.pin2.attemptsRemaining = remaining
      let card = VirtualIDCard(snapshot: state)

      let result = await card.authorizeQualifiedSignature(pin2: "000000")
      let latest = await card.inspect()

      XCTAssertEqual(result, .rejected(remaining: remaining - 1))
      XCTAssertEqual(
        latest.card.pin2.attemptsRemaining,
        remaining - 1)
    }
  }

  internal func testSignatureCertificateAndFaultsFailWithoutGuessing() async {
    for certificate in VirtualIDCard.CertificateState.allCases
    where certificate != .valid {
      var unavailable = VirtualIDCard.Scenario.registeredNearField.snapshot
      unavailable.card.signatureCertificate = certificate
      let card = VirtualIDCard(snapshot: unavailable)
      let result = await card.authorizeQualifiedSignature(
        pin2: unavailable.card.pin2.value)
      XCTAssertEqual(result, .certificateUnavailable)
      let latest = await card.inspect()
      XCTAssertEqual(latest.card.pin2.attemptsRemaining, 5)
      XCTAssertFalse(latest.device.pendingSigningRequest)
    }

    var interrupted = VirtualIDCard.Scenario.registeredNearField.snapshot
    interrupted.faults =
      VirtualIDCard.FaultPreset.responseLostAfterSignature.faults
    let interruptedCard = VirtualIDCard(snapshot: interrupted)
    let interruptedResult = await interruptedCard.authorizeQualifiedSignature(
      pin2: interrupted.card.pin2.value)
    XCTAssertEqual(
      interruptedResult,
      .transportFailure(.connectionLost))
    let latest = await interruptedCard.inspect()
    XCTAssertEqual(latest.card.pin2.attemptsRemaining, 5)
    XCTAssertFalse(latest.device.pendingSigningRequest)
  }

  internal func testUnreachableCardsAndPreCommandFaultSpendNothing() async {
    var states: [VirtualIDCard.Snapshot] = []
    var absent = VirtualIDCard.Scenario.registeredNearField.snapshot
    absent.card.cardPresent = false
    states.append(absent)
    var readerDisconnected = VirtualIDCard.Scenario.activatedReader.snapshot
    readerDisconnected.card.readerConnected = false
    states.append(readerDisconnected)
    var commandInterrupted = VirtualIDCard.Scenario.registeredNearField.snapshot
    commandInterrupted.faults =
      VirtualIDCard.FaultPreset.cardRemovedDuringSignature.faults
    states.append(commandInterrupted)

    for state in states {
      let card = VirtualIDCard(snapshot: state)
      guard
        case .transportFailure = await card.authorizeQualifiedSignature(
          pin2: state.card.pin2.value)
      else {
        XCTFail("unreachable virtual card did not fail at its boundary")
        continue
      }
      let latest = await card.inspect()
      XCTAssertEqual(latest.card.pin2.attemptsRemaining, 5)
      XCTAssertFalse(latest.device.pendingSigningRequest)
    }
  }
}
