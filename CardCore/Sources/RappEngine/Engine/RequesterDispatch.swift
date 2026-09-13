// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// The caller's next step after an inbound operation message.
internal enum RequesterDispatch: Equatable {
  /// A peer cancellation was journaled.
  case cancellationReceived(operationIdentifier: Data, state: OperationState)
  /// An advisory progress event was ignored without an error response.
  case ignoredProgress(operationIdentifier: Data)
  /// A stale reference; answer it and change nothing.
  case ignoredStale(operationIdentifier: Data, response: TypedMessage)
  /// Not an operation message; the operation layer is unaffected.
  case notOperation(TypedMessage)
  /// The peer already serves an operation on this pairing.
  case peerBusy
  /// The peer answered a stale reference; an ordinary race.
  case peerUnknownOperation(operationIdentifier: Data?)
  /// The proxy is ready; the requester decides whether to commit.
  case prepared(operationIdentifier: Data)
  /// An advisory progress event arrived for this active operation.
  case progress(operationIdentifier: Data, event: ProgressEvent)
  /// Release this acknowledgement for the completed result.
  case sendResultAcknowledgement(operationIdentifier: Data, message: TypedMessage)
  /// An authenticated status report was stored as an annotation.
  case statusAnnotated(operationIdentifier: Data)
  /// The operation reached its journaled terminal state, and why.
  case terminal(operationIdentifier: Data, state: OperationState, reason: ResultError)
}
