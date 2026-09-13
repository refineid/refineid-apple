// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

// The cases are ordered as the engine emits them through an operation's life,
// so the source reads in the order the caller meets them.
// swiftlint:disable sorted_enum_cases

/// What the caller does next.
///
/// Every outcome is data. The engine decides what must happen and the caller
/// performs it, so nothing here touches a card, a transport, or a screen.
public enum RappBridgeActionKind: Equatable, Sendable {
  /// Release the accompanying frame on the authenticated session.
  case sendFrame
  /// Run the profile's bounded prerequisite reads before asking consent.
  case inspectPrerequisites
  /// Ask the holder to approve exactly the accompanying operation.
  case awaitUserApproval
  /// Run the authorized read; it touches no credential retry budget.
  case executeSafeRead
  /// Take the one authorized card command.
  case executeCardCommand
  /// Release this acknowledgement for the completed result.
  case resultAcknowledgment
  /// The operation answered.
  case completed
  /// The operation ended without an answer.
  case terminal
  /// The operation was cancelled with nothing transmitted.
  case cancelled
  /// A cancellation arrived after the commit, so it is advisory only.
  case advisoryCancellation
  /// The peer acknowledged the retained result.
  case resultAcknowledged
  /// Advisory progress update reported by peer.
  case progress
  /// The peer already serves an operation on this pairing.
  case peerBusy
  /// The peer answered a stale reference; an ordinary race.
  case peerUnknownOperation
  /// A repeated message that changes nothing.
  case ignoredDuplicate
  /// Nothing to do.
  case noAction
  /// The session closed.
  case sessionClosed
  /// The pairing ended.
  case pairRevoked
}

// swiftlint:enable sorted_enum_cases
