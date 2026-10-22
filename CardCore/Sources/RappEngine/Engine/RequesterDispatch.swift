// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// What an inbound message means to the requester.
internal enum RequesterDispatch: Equatable {
  /// The custodian's card is present, with its fingerprint, or absent
  /// (RAPP v26.10.22 §8.4).
  case cardStatus(RappCardStatus)
  /// The live operation completed.
  case completed(operationIdentifier: RappOperationIdentifier, result: CardOperationResult)
  /// The live operation ended without completing: rejected or cancelled,
  /// with why.
  case ended(operationIdentifier: RappOperationIdentifier, status: ResultStatus, error: ResultError)
  /// A message for an operation that is no longer live.
  case ignored(operationIdentifier: RappOperationIdentifier)
  /// Not an operation message.
  case notOperation(TypedMessage)
  /// An `error` naming no operation.
  case peerError(ResultError)
  /// The live operation's state changed.
  case progress(operationIdentifier: RappOperationIdentifier, event: ProgressEvent)
  /// The custodian refused the request before admitting it (`busy`,
  /// `duplicate_operation`).
  case refused(operationIdentifier: RappOperationIdentifier, error: ResultError)
}
