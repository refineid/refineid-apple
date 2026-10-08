// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

extension ResultStatus {
  /// The terminal journal state a non-successful status records.
  ///
  /// A completed status has no failure state; it becomes terminal only once
  /// the requester acknowledges the retained result.
  internal var failureState: OperationState? {
    switch self {
    case .completed:
      nil

    case .cancelled:
      .cancelled

    case .rejected:
      .rejected

    case .credentialRejected:
      .credentialRejected

    case .ambiguous:
      .ambiguous
    }
  }
}
