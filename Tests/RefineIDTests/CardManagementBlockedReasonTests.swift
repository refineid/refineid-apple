// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CardCore
import XCTest

@testable import RefineIDTestHost

/// A form whose entries are all valid either can go to the card or says
/// why it cannot; the form's button and its stated reason never disagree.
@MainActor
internal final class CardManagementBlockedReasonTests: XCTestCase {
  private static let roles: [CredentialRole] = [.pin1, .pin2, .puk]
  private static let lastTry: UInt8 = 1
  private static let noTries: UInt8 = 0

  private static func model(_ outcome: RetryProbeOutcome) -> CardManagementModel {
    let model = CardManagementModel(
      transport: .reader,
      activationRequired: false,
      cardAccessNumber: nil,
      activation: nil,
      activationNeeds: nil,
      pinLengths: nil
    )
    model.apply(
      CardMaintenance.Snapshot(
        report: CredentialProbeReport(pin1: outcome, pin2: outcome, puk: outcome),
        activationNeeds: nil,
        activation: nil,
        pinLengths: nil),
      preservingOutcome: false)
    return model
  }

  private static func remaining(_ attempts: UInt8) throws -> RetryProbeOutcome {
    .remaining(try XCTUnwrap(RetryCount(attemptsRemaining: attempts)))
  }

  private func assertAgree(_ outcome: RetryProbeOutcome, proceeds: Bool) {
    let model = Self.model(outcome)
    for role in Self.roles {
      XCTAssertEqual(model.allowsCredentialOperation(spending: role), proceeds)
      let reason = model.blockedReason(presenting: PresentedCredential(role), spending: role)
      XCTAssertEqual(reason == nil, proceeds)
    }
  }

  internal func testEveryReadingEitherProceedsOrSaysWhy() throws {
    assertAgree(try Self.remaining(RetryCount.pristineAllowance), proceeds: true)
    assertAgree(try Self.remaining(RetryFloor.minimumAttemptsToProceed), proceeds: true)
    assertAgree(
      try Self.remaining(RetryFloor.minimumAttemptsToProceed - Self.lastTry), proceeds: false)
    assertAgree(try Self.remaining(Self.lastTry), proceeds: false)
    assertAgree(try Self.remaining(Self.noTries), proceeds: true)
    assertAgree(.locked, proceeds: true)
    assertAgree(.invalidated, proceeds: true)
    assertAgree(.noInformation, proceeds: false)
    assertAgree(.other(StatusWord.conditionsNotSatisfied.encoded), proceeds: false)
  }

  internal func testAnUnreadableCounterIsNamedInFull() {
    let model = Self.model(.other(StatusWord.conditionsNotSatisfied.encoded))
    XCTAssertEqual(
      model.blockedReason(presenting: .pin1, spending: .pin1),
      PresentedCredential.pin1.unreadableCounterMessage)
    XCTAssertEqual(
      model.blockedReason(presenting: .puk, spending: .puk),
      PresentedCredential.puk.unreadableCounterMessage)
  }

  internal func testAPukReportedVerifiedHasNoCountAndSaysSo() {
    let model = Self.model(.verified)
    XCTAssertFalse(model.allowsCredentialOperation(spending: .puk))
    XCTAssertEqual(
      model.blockedReason(presenting: .puk, spending: .puk),
      PresentedCredential.puk.unreadableCounterMessage)
    XCTAssertNil(model.blockedReason(presenting: .pin1, spending: .pin1))
  }

  internal func testAnActivationIsJudgedOnThePukItsCodeIs() throws {
    let model = CardManagementModel(
      transport: .reader,
      activationRequired: false,
      cardAccessNumber: nil,
      activation: .organization,
      activationNeeds: nil,
      pinLengths: nil
    )
    let low = try Self.remaining(RetryFloor.minimumAttemptsToProceed - Self.lastTry)
    let full = try Self.remaining(RetryCount.pristineAllowance)
    model.apply(
      CardMaintenance.Snapshot(
        report: CredentialProbeReport(pin1: full, pin2: full, puk: low),
        activationNeeds: nil,
        activation: .organization,
        pinLengths: nil),
      preservingOutcome: false)
    XCTAssertNotNil(model.activationBlockedReason)
  }

  internal func testNoReadingYetLeavesTheFormToTheFreshProbe() {
    let model = CardManagementModel(
      transport: .reader,
      activationRequired: false,
      cardAccessNumber: nil,
      activation: nil,
      activationNeeds: nil,
      pinLengths: nil
    )
    XCTAssertNil(model.blockedReason(presenting: .puk, spending: .puk))
  }
}
