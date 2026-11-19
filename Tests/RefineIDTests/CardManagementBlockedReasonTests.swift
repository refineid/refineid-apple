// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CardCore
import Testing

@testable import RefineIDTestHost

/// A form whose entries are all valid either can go to the card or says
/// why it cannot; the form's button and its stated reason never disagree.
@MainActor
@Suite(.serialized)
internal final class CardManagementBlockedReasonTests {
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
    .remaining(try #require(RetryCount(attemptsRemaining: attempts)))
  }

  private func assertAgree(_ outcome: RetryProbeOutcome, proceeds: Bool) {
    let model = Self.model(outcome)
    for role in Self.roles {
      #expect((model.allowsCredentialOperation(spending: role)) == (proceeds))
      let reason = model.blockedReason(presenting: PresentedCredential(role), spending: role)
      #expect((reason == nil) == (proceeds))
    }
  }

  @Test
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

  @Test
  internal func testAnUnreadableCounterIsNamedInFull() {
    let model = Self.model(.other(StatusWord.conditionsNotSatisfied.encoded))
    #expect(
      (model.blockedReason(presenting: .pin1, spending: .pin1))
        == (PresentedCredential.pin1.unreadableCounterMessage))
    #expect(
      (model.blockedReason(presenting: .puk, spending: .puk))
        == (PresentedCredential.puk.unreadableCounterMessage))
  }

  @Test
  internal func testAPukReportedVerifiedHasNoCountAndSaysSo() {
    let model = Self.model(.verified)
    #expect(!(model.allowsCredentialOperation(spending: .puk)))
    #expect(
      (model.blockedReason(presenting: .puk, spending: .puk))
        == (PresentedCredential.puk.unreadableCounterMessage))
    #expect((model.blockedReason(presenting: .pin1, spending: .pin1)) == nil)
  }

  @Test
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
    #expect((model.activationBlockedReason) != nil)
  }

  @Test
  internal func testNoReadingYetLeavesTheFormToTheFreshProbe() {
    let model = CardManagementModel(
      transport: .reader,
      activationRequired: false,
      cardAccessNumber: nil,
      activation: nil,
      activationNeeds: nil,
      pinLengths: nil
    )
    #expect((model.blockedReason(presenting: .puk, spending: .puk)) == nil)
  }
}
