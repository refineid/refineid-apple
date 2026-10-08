// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation
import Testing

@testable import RappEngine

/// A terminal requester operation leaves no stored journal behind.
///
/// Only interrupted records (ambiguous or delivery-uncertain) stay stored
/// for reconciliation.
@Suite("RAPP requester journal cleanup")
internal struct RequesterJournalCleanupTests {
  /// A completed operation releases its result, so its journal is removed
  /// when the acknowledgement goes out.
  @Test
  internal func completedOperationsLeaveNoStoredJournal() throws {
    let happy = try driveHappyPath()
    #expect(happy.store.requesterRemovals == [EngineFixture.operationIdentifier])
    #expect(
      !happy.store.requesterWrites.contains { $0.state == .completed },
      "completion removes the journal instead of persisting one more state")
  }

  /// A denied operation is terminal at once, so the denial removes its
  /// journal.
  @Test
  internal func deniedOperationsLeaveNoStoredJournal() throws {
    var store = MemoryJournalStore()
    var proxy = ProxyOperationEngine(grantedProfiles: [.authentication], recovered: [])
    var requester = RequesterOperationEngine(recovered: [])
    let request = try engineRequest(operation: signingOperation())
    let identifier = request.operationIdentifier
    let requestMessage = try requester.begin(request, store: &store)
    _ = try proxy.receive(
      requestMessage, store: &store, nowMilliseconds: EngineFixture.nowMilliseconds,
      maximumLifetimeMilliseconds: EngineFixture.maximumLifetimeMilliseconds)
    try proxy.prerequisitesComplete(operationIdentifier: identifier)
    let denial = try proxy.finishFailure(
      operationIdentifier: identifier, failure: .userDenied, store: &store)
    guard case .sendFailure(let deniedMessage, _) = denial else {
      Issue.record("a denial produces a failure result")
      return
    }
    let dispatch = try requester.receive(deniedMessage, store: &store)
    #expect(
      dispatch
        == .terminal(
          operationIdentifier: identifier, state: .rejected, status: .rejected,
          error: .userCancelled))
    #expect(store.requesterRemovals == [identifier])
  }

  /// Closing the session cancels unanswered safe reads, which touched no
  /// credential and have nothing left to reconcile, so their journals go.
  @Test
  internal func sessionCloseRemovesCancelledJournals() throws {
    var store = MemoryJournalStore()
    var requester = RequesterOperationEngine(recovered: [])
    let first = try engineRequest(operation: .inspectCard)
    let second = try engineRequest(
      operation: .readIdentity, operationIdentifier: EngineFixture.secondOperationIdentifier)
    _ = try requester.begin(first, store: &store)
    _ = try requester.begin(second, store: &store)

    let classified = requester.sessionClosed(store: &store)

    #expect(classified.map(\.state) == [.cancelled, .cancelled])
    #expect(store.requesterRemovals == [first.operationIdentifier, second.operationIdentifier])
  }

  /// An unanswered consequential request may have been approved and executed
  /// by the custodian, so the close leaves it ambiguous and stored for
  /// reconciliation (section 8.3).
  @Test
  internal func sessionCloseKeepsAmbiguousJournals() throws {
    var store = MemoryJournalStore()
    var requester = RequesterOperationEngine(recovered: [])
    let request = try engineRequest(operation: signingOperation())
    _ = try requester.begin(request, store: &store)

    let classified = requester.sessionClosed(store: &store)

    #expect(classified.map(\.state) == [.ambiguous])
    #expect(store.requesterRemovals.isEmpty)
    #expect(store.requesterWrites.last?.state == .ambiguous)
  }

  /// Finishing operations in bulk leaves nothing stored: every persisted
  /// journal is removed at its terminal state, so the live set stays
  /// empty no matter how many operations ran.
  @Test
  internal func repeatedTerminalOperationsLeaveNoStoredJournals() throws {
    var store = MemoryJournalStore()
    var denied: [Data] = []
    for fill in 0..<5 {
      var proxy = ProxyOperationEngine(grantedProfiles: [.authentication], recovered: [])
      var requester = RequesterOperationEngine(recovered: [])
      let identifier = Data(
        repeating: UInt8(fill), count: EngineFixture.operationIdentifier.count)
      let request = try engineRequest(
        operation: signingOperation(), operationIdentifier: identifier)
      let requestMessage = try requester.begin(request, store: &store)
      _ = try proxy.receive(
        requestMessage, store: &store, nowMilliseconds: EngineFixture.nowMilliseconds,
        maximumLifetimeMilliseconds: EngineFixture.maximumLifetimeMilliseconds)
      try proxy.prerequisitesComplete(operationIdentifier: identifier)
      let denial = try proxy.finishFailure(
        operationIdentifier: identifier, failure: .userDenied, store: &store)
      guard case .sendFailure(let deniedMessage, _) = denial else {
        Issue.record("a denial produces a failure result")
        return
      }
      _ = try requester.receive(deniedMessage, store: &store)
      denied.append(identifier)
    }

    let persisted = Set(store.requesterWrites.map(\.operationIdentifier))
    let removed = Set(store.requesterRemovals)
    #expect(persisted == Set(denied))
    #expect(removed == Set(denied))
    #expect(persisted.subtracting(removed).isEmpty)
  }

  /// A late status report annotates a terminal operation in memory only;
  /// it must not resurrect the removed journal back into storage.
  @Test
  internal func lateStatusDoesNotResurrectRemovedJournals() throws {
    var store = MemoryJournalStore()
    var requester = RequesterOperationEngine(recovered: [])
    let request = try engineRequest(operation: .inspectCard)
    let identifier = request.operationIdentifier
    _ = try requester.begin(request, store: &store)
    _ = try requester.cancel(operationIdentifier: identifier, store: &store)
    let writesAfterCancel = store.requesterWrites.count
    #expect(store.requesterRemovals == [identifier])

    let report = StatusReport(
      operationIdentifier: identifier, known: true, state: .cancelled,
      requestHash: nil)
    let dispatch = try requester.receive(.operationStatus(report), store: &store)

    #expect(dispatch == .statusAnnotated(operationIdentifier: identifier))
    #expect(store.requesterWrites.count == writesAfterCancel)
  }
}
