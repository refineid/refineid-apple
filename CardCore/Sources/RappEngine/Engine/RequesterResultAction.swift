// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// What arrives with a peer result.
internal enum RequesterResultAction: Equatable {
  case sendAcknowledgement(TypedMessage)
  case terminal(state: OperationState, status: ResultStatus, error: ResultError?)
}
