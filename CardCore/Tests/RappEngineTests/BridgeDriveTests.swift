// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation
import Testing

@testable import RappEngine

/// Operations end to end between the two operation bridges (RAPP v26.10.22
/// §8, §9).
@Suite("RAPP operations between the bridges")
internal struct BridgeDriveTests {
  private static let start = OperationFixture.startMilliseconds
  private static let lifetime = OperationFixture.lifetimeMilliseconds
  /// The smallest step of the millisecond clock.
  private static let tick: UInt64 = 1
  /// A synthetic answer to reset.
  private static let answerToReset = Data("ATR".utf8)

  private static func established(_ grants: [ProfileName] = everyProfile) throws -> LiveSession {
    try establishedSession(try PairedBridges.pair(granting: grants), nowMilliseconds: start)
  }

  /// A browser authentication the requester began and the custodian holds,
  /// with the card taken and the PIN asked for.
  private static func authenticationAwaitingConsent(
    _ session: LiveSession, _ identifier: RappOperationIdentifier
  ) throws {
    let request = try session.requester.beginBrowserAuthentication(
      operationId: identifier, origin: OperationFixture.origin, keyProfile: .ecdsaP256,
      algorithm: .ecdsaSha256, digest: OperationFixture.digest, localStartMs: start,
      expiresAfterMs: lifetime)
    guard
      case .custodianStep(identifier, .inspectPrerequisites, let descriptor) = try deliver(
        request, to: session.custodian, at: start)
    else { throw DriveFailure(description: "the custodian takes the card first") }
    #expect(descriptor.kind == .browserAuthenticate)
    #expect(descriptor.displayContext == OperationFixture.origin)
    guard
      case .custodianStep(identifier, .awaitUserApproval, _) = try session.custodian
        .prerequisitesComplete(operationId: identifier, nowMs: start)
    else { throw DriveFailure(description: "an authentication takes its PIN") }
  }

  @Test("A browser authentication completes end to end with its progress")
  internal func browserAuthenticationCompletes() throws {
    let session = try Self.established()
    let identifier = OperationFixture.operationIdentifier
    try Self.authenticationAwaitingConsent(session, identifier)
    let consent = try session.custodian.reportProgress(
      operationId: identifier, event: .consentShown)
    #expect(
      try deliver(consent, to: session.requester, at: Self.start)
        == .progress(identifier, .consentShown))
    guard
      case .custodianStep(identifier, .executeCardCommand, let command) = try session.custodian
        .approve(operationId: identifier, approvedAtMs: OperationFixture.approvalMilliseconds)
    else { throw DriveFailure(description: "the approval hands out the card command") }
    #expect(command.digest == OperationFixture.digest)
    let answer = try session.custodian.completeSignature(
      operationId: identifier, signature: OperationFixture.signature)
    #expect(
      try deliver(answer, to: session.requester, at: Self.start)
        == .completed(identifier, .signature(OperationFixture.signature)))
    #expect(
      (try? session.custodian.reportProgress(operationId: identifier, event: .cardWaitEnded))
        == nil, "an operation with its result reports no progress")
  }

  @Test("A read takes its turn and asks the holder nothing")
  internal func readAsksNothing() throws {
    let session = try Self.established()
    let identifier = OperationFixture.operationIdentifier
    let request = try session.requester.beginInspectCard(
      operationId: identifier, localStartMs: Self.start, expiresAfterMs: Self.lifetime)
    guard
      case .custodianStep(identifier, .inspectPrerequisites, _) = try deliver(
        request, to: session.custodian, at: Self.start)
    else { throw DriveFailure(description: "a read takes its turn on the card") }
    guard
      case .custodianStep(identifier, .executeSafeRead, let read) = try session.custodian
        .prerequisitesComplete(operationId: identifier, nowMs: Self.start)
    else { throw DriveFailure(description: "a read asks the holder nothing") }
    #expect(read.kind == .inspectCard)
    #expect(
      (try? session.custodian.approve(operationId: identifier, approvedAtMs: Self.start)) == nil,
      "a read has no PIN to approve")
    let answer = try session.custodian.completeInspection(
      operationId: identifier, answerToReset: Self.answerToReset)
    #expect(
      try deliver(answer, to: session.requester, at: Self.start)
        == .completed(identifier, .inspection(answerToReset: Self.answerToReset)))
  }

  @Test(
    "Every way the custodian ends an operation reaches the requester by name",
    arguments: [
      RappTerminalReason.userCancelled, .unsupportedParameter, .retryFloor, .cardError,
      .operationFailed,
    ])
  internal func terminalReasons(reason: RappTerminalReason) throws {
    let session = try Self.established()
    let identifier = OperationFixture.operationIdentifier
    try Self.authenticationAwaitingConsent(session, identifier)
    let custodian = session.custodian
    let ended: RappBridgeAction
    switch reason {
    case .userCancelled:
      ended = try custodian.deny(operationId: identifier)

    case .unsupportedParameter:
      ended = try custodian.requestInvalidOrUnsupported(operationId: identifier)

    default:
      _ = try custodian.approve(
        operationId: identifier, approvedAtMs: OperationFixture.approvalMilliseconds)
      ended =
        switch reason {
        case .retryFloor:
          try custodian.retryFloor(operationId: identifier)

        case .cardError:
          try custodian.cardError(operationId: identifier)

        default:
          try custodian.operationFailed(operationId: identifier)
        }
    }
    #expect(
      try deliver(ended, to: session.requester, at: Self.start) == .terminal(identifier, reason))
  }

  @Test("An operation whose deadline passes before the card is commanded is cancelled")
  internal func deadlineExpiry() throws {
    let session = try Self.established()
    let late = Self.start + Self.lifetime + Self.tick
    let first = OperationFixture.operationIdentifier
    let request = try session.requester.beginInspectCard(
      operationId: first, localStartMs: Self.start, expiresAfterMs: Self.lifetime)
    _ = try deliver(request, to: session.custodian, at: Self.start)
    let cancelled = try session.custodian.prerequisitesComplete(operationId: first, nowMs: late)
    #expect(
      try deliver(cancelled, to: session.requester, at: late)
        == .terminal(first, .operationExpired))

    let second = OperationFixture.otherOperation
    try Self.authenticationAwaitingConsent(session, second)
    #expect(
      try session.custodian.expireDue(nowMs: Self.start + Self.lifetime) == .noAction,
      "nothing is due on the deadline itself")
    let expired = try session.custodian.expireDue(nowMs: late)
    #expect(
      try deliver(expired, to: session.requester, at: late)
        == .terminal(second, .operationExpired))
    #expect(
      (try? session.custodian.approve(operationId: second, approvedAtMs: late)) == nil,
      "an expired operation takes no approval")
  }

  @Test("An approval after the deadline cancels instead of commanding the card")
  internal func lateApprovalCancels() throws {
    let session = try Self.established()
    let identifier = OperationFixture.operationIdentifier
    try Self.authenticationAwaitingConsent(session, identifier)
    let late = Self.start + Self.lifetime + Self.tick
    let cancelled = try session.custodian.approve(operationId: identifier, approvedAtMs: late)
    #expect(
      try deliver(cancelled, to: session.requester, at: late)
        == .terminal(identifier, .operationExpired))
  }

  @Test("The card's status names its certificate's fingerprint or its absence, and the reader")
  internal func cardStatus() throws {
    let session = try Self.established()
    let fingerprint = try #require(
      RappCertificateFingerprint(certificate: OperationFixture.certificate))
    for card in [RappCardPresence.present(fingerprint), .absent] {
      for reader in [RappCardReader.attached, .absent] {
        let status = RappCardStatus(card: card, reader: reader)
        let report = try session.custodian.reportCardStatus(status)
        #expect(try deliver(report, to: session.requester, at: Self.start) == .cardStatus(status))
      }
    }
    #expect(
      (try? session.requester.reportCardStatus(RappCardStatus(card: .absent, reader: .absent)))
        == nil,
      "only the custodian reports the card")
  }

  @Test("A batch signs every document, more than any earlier limit")
  internal func largeBatchCompletes() throws {
    let session = try Self.established()
    let identifier = OperationFixture.operationIdentifier
    let documents = (Int.zero..<OperationFixture.largeBatchSize).map { "Document \($0).pdf" }
    let digests = documents.map { _ in OperationFixture.digest }
    let request = try session.requester.beginBatchSignDocuments(
      operationId: identifier, documentNames: documents, keyProfile: .ecdsaP256,
      algorithm: .ecdsaSha256, digests: digests, localStartMs: Self.start,
      expiresAfterMs: Self.lifetime)
    _ = try deliver(request, to: session.custodian, at: Self.start)
    guard
      case .custodianStep(identifier, .awaitUserApproval, let consent) = try session.custodian
        .prerequisitesComplete(operationId: identifier, nowMs: Self.start)
    else { throw DriveFailure(description: "a batch asks for PIN 2 once") }
    #expect(consent.documentNames == documents)
    _ = try session.custodian.approve(
      operationId: identifier, approvedAtMs: OperationFixture.approvalMilliseconds)
    #expect(
      (try? session.custodian.completeBatch(operationId: identifier)) == nil,
      "a batch with documents left does not complete")
    let signatures = documents.map { Data("signature of \($0)".utf8) }
    for signature in signatures {
      try session.custodian.recordBatchSignature(operationId: identifier, signature: signature)
    }
    #expect(
      (try? session.custodian.recordBatchSignature(
        operationId: identifier, signature: OperationFixture.signature)) == nil,
      "a batch takes no signature past its last document")
    let answer = try session.custodian.completeBatch(operationId: identifier)
    #expect(
      try deliver(answer, to: session.requester, at: Self.start)
        == .completed(identifier, .signatures(signatures)))
  }

  @Test("A requester runs one operation at a time, of a granted profile, each identifier once")
  internal func requesterLocalRules() throws {
    let session = try Self.established([.cardStatus])
    let first = OperationFixture.operationIdentifier
    let second = OperationFixture.otherOperation
    let request = try session.requester.beginInspectCard(
      operationId: first, localStartMs: Self.start, expiresAfterMs: Self.lifetime)
    #expect(throws: RappBindingError.WrongPhase) {
      _ = try session.requester.beginReadIdentity(
        operationId: second, localStartMs: Self.start, expiresAfterMs: Self.lifetime)
    }
    _ = try deliver(request, to: session.custodian, at: Self.start)
    _ = try session.custodian.prerequisitesComplete(operationId: first, nowMs: Self.start)
    let answer = try session.custodian.completeInspection(
      operationId: first, answerToReset: Self.answerToReset)
    _ = try deliver(answer, to: session.requester, at: Self.start)
    #expect(throws: RappBindingError.InvalidInput) {
      _ = try session.requester.beginReadCertificate(
        operationId: second, signatureCertificate: false, localStartMs: Self.start,
        expiresAfterMs: Self.lifetime)
    }
    #expect(throws: RappBindingError.InvalidInput) {
      _ = try session.requester.beginInspectCard(
        operationId: first, localStartMs: Self.start, expiresAfterMs: Self.lifetime)
    }
    _ = try session.requester.beginReadIdentity(
      operationId: second, localStartMs: Self.start, expiresAfterMs: Self.lifetime)
  }
}
