// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation
import Testing

@testable import RappEngine

/// What closing and revoking must do to the operations and the pairing.
@Suite
internal struct SessionCloseBehaviorTests {
  private static func request(
    operationIdentifier: Data = EngineFixture.operationIdentifier
  ) throws -> OperationRequest {
    try OperationRequest(
      operationIdentifier: operationIdentifier,
      pairIdentifier: EngineFixture.pairIdentifier,
      sessionIdentifier: EngineFixture.sessionIdentifier,
      profile: ProfileName.authentication,
      localStartMilliseconds: EngineFixture.startMilliseconds,
      expiresAfterMilliseconds: EngineFixture.expiresAfterMilliseconds,
      operation: .browserAuthenticate(
        origin: EngineFixture.origin,
        keyProfile: .rsa3072,
        algorithm: .rsaPkcs1Sha256,
        digest: EngineFixture.digest))
  }

  /// The failure taxonomy names revocation only for a rejected credential
  /// among the result-carried failures.
  @Test
  internal func onlyACredentialRejectionRevokesThePairing() throws {
    let reference = try OperationReference(of: Self.request())
    let rejected = TypedMessage.operationResult(
      .failure(reference: reference, failure: .credentialRejected))
    let denied = TypedMessage.operationResult(
      .failure(reference: reference, failure: .userDenied))
    #expect(RappOperationBridge.failureRevokesPairing(rejected))
    #expect(!RappOperationBridge.failureRevokesPairing(denied))
    #expect(
      !RappOperationBridge.failureRevokesPairing(
        .error(.operationFailed(operationIdentifier: nil))))
  }

  /// A rejected credential closes the session with its result (INV-16).
  @Test
  internal func aCredentialRejectionClosesTheSession() throws {
    var store = MemoryJournalStore()
    var proxy = ProxyOperationEngine(grantedProfiles: [.authentication], recovered: [])
    let request = try Self.request()
    _ = try proxy.receive(
      .operationRequest(request), store: &store,
      nowMilliseconds: EngineFixture.nowMilliseconds,
      maximumLifetimeMilliseconds: EngineFixture.maximumLifetimeMilliseconds)
    try proxy.prerequisitesComplete(operationIdentifier: request.operationIdentifier)

    let dispatch = try proxy.finishFailure(
      operationIdentifier: request.operationIdentifier,
      failure: .credentialRejected,
      store: &store)

    guard case .sendFailure(let message, let closesSession) = dispatch else {
      Issue.record("a rejected credential produces a failure result")
      return
    }
    #expect(closesSession)
    #expect(RappOperationBridge.failureRevokesPairing(message))
  }

  /// The proxy's card leaving closes the session and leaves the pairing.
  @Test
  internal func cardUnavailableClosesTheSessionOnly() {
    #expect(FieldSpec.closeReasons.contains(CloseReasonName.cardUnavailable))
    #expect(!CloseReasonName.revokesPairing(CloseReasonName.cardUnavailable))
    #expect(CloseReasonName.revokesPairing(CloseReasonName.pairingRevoked))
  }

  /// A decrypted frame that breaks the protocol must leave the channel
  /// able to seal the close notice the violation owes the peer.
  @Test
  internal func aViolationStillSealsTheCloseNotice() throws {
    let profiles: [ProfileName] = [.authentication]
    let peers = try runPairing(offer: makeOffer(profiles: profiles), grants: profiles)
    var (requester, proxy) = try runSession(peers)

    // Authenticated bytes that are no envelope at all: the proxy decrypts
    // them, fails the decode, and must classify a violation.
    let garbage = try requester.sealPayload(Data("not an envelope".utf8))
    #expect(throws: SessionError.unexpectedMessage) {
      _ = try proxy.open(garbage)
    }

    let notice = try proxy.seal(
      .sessionClose,
      body: [
        "reason": .text("protocol_violation"),
        "last_received_sequence": .unsigned(proxy.lastReceivedSequence),
      ])
    let received = try requester.open(notice)
    #expect(received.messageType == .sessionClose)
  }

  /// One record's failed terminal write must not leave the other live
  /// operations unclassified when the session closes.
  @Test
  internal func aFailedWriteDoesNotStopCloseClassification() throws {
    var store = MemoryJournalStore()
    var requester = RequesterOperationEngine(recovered: [])
    let first = try Self.request()
    let second = try Self.request(
      operationIdentifier: EngineFixture.secondOperationIdentifier)
    _ = try requester.begin(first, store: &store)
    _ = try requester.begin(second, store: &store)

    store.failNextWrite = true
    let classified = requester.sessionClosed(store: &store)

    #expect(
      classified.map(\.operationIdentifier)
        == [EngineFixture.secondOperationIdentifier])
    #expect(classified.map(\.state) == [.ambiguous])
  }
}
