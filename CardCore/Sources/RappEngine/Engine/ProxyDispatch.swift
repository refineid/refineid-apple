// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// The bounded step a proxy adapter performs next.
///
/// Every outcome is data. The engine decides what must happen and the adapter
/// performs it, so nothing here touches a card, a transport, or a screen.
internal enum ProxyDispatch: Equatable {
  /// Take the one authorized card command; its in-flight entry is durable.
  case beginCardCommand(operationIdentifier: Data)
  /// Run the authorized read; it touches no credential retry budget.
  case executeSafeRead(operationIdentifier: Data, read: AuthorizedSafeRead)
  /// An identical retransmission joined the operation already under way.
  case ignoredDuplicate(operationIdentifier: Data)
  /// A stale reference; answer it and change nothing.
  case ignoredStale(operationIdentifier: Data, response: TypedMessage)
  /// Run the profile's bounded prerequisite reads before asking consent.
  case inspectPrerequisites(operationIdentifier: Data)
  /// Not an operation message; the operation layer is unaffected.
  case notOperation(TypedMessage)
  /// The requester acknowledged the retained result.
  case resultAcknowledged(operationIdentifier: Data)
  /// Send this message on the authenticated session.
  case send(TypedMessage)
  /// Send these messages in order, such as a status report and the result
  /// it re-delivers.
  case sendAll([TypedMessage])
  /// Send this failure, then close the session if the failure demands it.
  case sendFailure(message: TypedMessage, closeSession: Bool)
}
