// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

@testable import CardCore

/// Remembers what the card already answered.
///
/// At-most-once has to outlive the process, because the counter it protects
/// does. An app that dies between reaching the card and answering the peer
/// would otherwise reach the card again on the retry, and a PIN attempt
/// spent that way does not come back.
public protocol SignRelayJournal: Sendable {
  /// The answer already given for `requestID`, if there is one.
  func answer(for requestID: UUID) throws -> PersistentRelayMessage?

  /// Records the answer given for `requestID`.
  func record(_ answer: PersistentRelayMessage, for requestID: UUID) throws
}
