// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CardCore
import Testing

@Suite(.serialized)
internal final class VirtualIDCardSigningTests {
  @Test
  internal func testQualifiedSignatureSuccessRestoresPIN2Allowance() async {
    var state = VirtualIDCard.Scenario.registeredNearField.snapshot
    state.card.pin2.attemptsRemaining = 3
    let card = VirtualIDCard(snapshot: state)

    let result = await card.authorizeQualifiedSignature(
      pin2: state.card.pin2.value)
    let latest = await card.inspect()

    expectState(result == .success, sourceLocation: #_sourceLocation)
    #expect(latest.card.pin2.attemptsRemaining == 5, sourceLocation: #_sourceLocation)
    expectState(!latest.device.pendingSigningRequest, sourceLocation: #_sourceLocation)
  }

  @Test
  internal func testInvalidSignatureEntriesNeverReachTheCard() async {
    let invalid = ["", "123", "1234567890123", "12a456"]
    for entry in invalid {
      var state = VirtualIDCard.Scenario.registeredNearField.snapshot
      state.card.pin2.attemptsRemaining = 4
      let card = VirtualIDCard(snapshot: state)

      let result = await card.authorizeQualifiedSignature(pin2: entry)
      expectState(result == .invalidEntry, sourceLocation: #_sourceLocation)
      let latest = await card.inspect()
      #expect(latest.card.pin2.attemptsRemaining == 4, sourceLocation: #_sourceLocation)
      expectState(!latest.device.pendingSigningRequest, sourceLocation: #_sourceLocation)
    }
  }

  @Test
  internal func testQualifiedSignatureNeverSpendsLastTwoAttempts() async {
    for remaining: UInt8 in 0...2 {
      var state = VirtualIDCard.Scenario.registeredNearField.snapshot
      state.card.pin2.attemptsRemaining = remaining
      let card = VirtualIDCard(snapshot: state)

      let result = await card.authorizeQualifiedSignature(pin2: "000000")
      let latest = await card.inspect()

      if remaining == 0 {
        expectState(result == .blocked, sourceLocation: #_sourceLocation)
      } else {
        expectState(
          result == (.refusedLowAttempts(remaining: remaining)), sourceLocation: #_sourceLocation)
      }
      #expect(latest.card.pin2.attemptsRemaining == remaining, sourceLocation: #_sourceLocation)
    }
  }

  @Test
  internal func testWrongSignaturePINConsumesExactlyOneEligibleAttempt() async {
    for remaining: UInt8 in 3...5 {
      var state = VirtualIDCard.Scenario.registeredNearField.snapshot
      state.card.pin2.attemptsRemaining = remaining
      let card = VirtualIDCard(snapshot: state)

      let result = await card.authorizeQualifiedSignature(pin2: "000000")
      let latest = await card.inspect()

      expectState(result == (.rejected(remaining: remaining - 1)), sourceLocation: #_sourceLocation)
      #expect(
        latest.card.pin2.attemptsRemaining == (remaining - 1), sourceLocation: #_sourceLocation)
    }
  }

  @Test
  internal func testSignatureCertificateAndFaultsFailWithoutGuessing() async {
    for certificate in VirtualIDCard.CertificateState.allCases
    where certificate != .valid {
      var unavailable = VirtualIDCard.Scenario.registeredNearField.snapshot
      unavailable.card.signatureCertificate = certificate
      let card = VirtualIDCard(snapshot: unavailable)
      let result = await card.authorizeQualifiedSignature(
        pin2: unavailable.card.pin2.value)
      expectState(result == .certificateUnavailable, sourceLocation: #_sourceLocation)
      let latest = await card.inspect()
      #expect(latest.card.pin2.attemptsRemaining == 5, sourceLocation: #_sourceLocation)
      expectState(!latest.device.pendingSigningRequest, sourceLocation: #_sourceLocation)
    }

    var interrupted = VirtualIDCard.Scenario.registeredNearField.snapshot
    interrupted.faults =
      VirtualIDCard.FaultPreset.responseLostAfterSignature.faults
    let interruptedCard = VirtualIDCard(snapshot: interrupted)
    let interruptedResult = await interruptedCard.authorizeQualifiedSignature(
      pin2: interrupted.card.pin2.value)
    expectState(
      interruptedResult == (.transportFailure(.connectionLost)), sourceLocation: #_sourceLocation)
    let latest = await interruptedCard.inspect()
    #expect(latest.card.pin2.attemptsRemaining == 5, sourceLocation: #_sourceLocation)
    expectState(!latest.device.pendingSigningRequest, sourceLocation: #_sourceLocation)
  }

  @Test
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
        Issue.record("unreachable virtual card did not fail at its boundary")
        continue
      }
      let latest = await card.inspect()
      #expect(latest.card.pin2.attemptsRemaining == 5, sourceLocation: #_sourceLocation)
      expectState(!latest.device.pendingSigningRequest, sourceLocation: #_sourceLocation)
    }
  }
}
