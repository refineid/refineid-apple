// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// Proxy's answer to a durable status query.
internal struct StatusReport: Equatable {
  internal var operationIdentifier: Data
  internal var known: Bool
  internal var state: OperationState?
  internal var requestHash: Data?
  /// Whether the operation is acknowledged and only its tombstone remains.
  internal var retired: Bool

  internal init(
    operationIdentifier: Data,
    known: Bool,
    state: OperationState?,
    requestHash: Data?,
    retired: Bool
  ) {
    self.operationIdentifier = operationIdentifier
    self.known = known
    self.state = state
    self.requestHash = requestHash
    self.retired = retired
  }

  /// A report of an operation that is not retired.
  internal init(
    operationIdentifier: Data,
    known: Bool,
    state: OperationState?,
    requestHash: Data?
  ) {
    self.init(
      operationIdentifier: operationIdentifier, known: known, state: state,
      requestHash: requestHash, retired: false)
  }
  /// A report naming an operation the peer does not know.
  internal init(operationIdentifier: Data, known: Bool) {
    self.init(
      operationIdentifier: operationIdentifier, known: known, state: nil, requestHash: nil)
  }
}
