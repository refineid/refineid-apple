// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

@testable import CardCore

/// Answers a paired requester's card requests, at most once each.
///
/// The card's retry counter does not go back up, so a request that arrives
/// twice must reach the card once. The answer is kept under the request's
/// identifier and replayed if the same identifier is asked again, which is
/// the whole of what at-most-once needs here.
///
/// This works on payloads rather than frames: the session owns the cipher,
/// and a second owner of it is a second place for the two to disagree.
public actor SignRelayProxy {
  /// Performs one request against the card.
  public typealias Perform = @Sendable (PersistentRelayMessage) async -> PersistentRelayMessage

  private let perform: Perform
  private let journal: (any SignRelayJournal)?
  private var answered: [UUID: PersistentRelayMessage] = [:]
  private var running: Set<UUID> = []

  /// Serves requests, performing each with `perform`.
  ///
  /// - Parameters:
  ///   - journal: where answers outlive the process; without one they last
  ///     only as long as this proxy does.
  ///   - perform: reaches the card.
  public init(journal: (any SignRelayJournal)? = nil, perform: @escaping Perform) {
    self.journal = journal
    self.perform = perform
  }

  /// Answers one request payload.
  ///
  /// A request already in flight is answered with nil rather than started a
  /// second time.
  ///
  /// - Parameter payload: the peer's opened request.
  /// - Returns: the answer's payload, or nil when the request is already
  ///   being performed.
  /// - Throws: when the payload is not a request this relay carries.
  public func answer(to payload: Data) async throws -> Data? {
    let request = try PersistentRelayMessage.decoded(payload)
    let requestID = request.requestID
    if let answer = try alreadyAnswered(requestID) {
      return try answer.encoded()
    }
    guard !running.contains(requestID) else { return nil }
    running.insert(requestID)
    let answer = await perform(request)
    running.remove(requestID)
    answered[requestID] = answer
    try? journal?.record(answer, for: requestID)
    return try answer.encoded()
  }

  /// What was already answered for this request, here or in the journal.
  private func alreadyAnswered(_ requestID: UUID) throws -> PersistentRelayMessage? {
    if let answer = answered[requestID] { return answer }
    guard let journalled = try journal?.answer(for: requestID) else { return nil }
    answered[requestID] = journalled
    return journalled
  }
}
