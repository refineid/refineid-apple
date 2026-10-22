// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// The holder's approval of one operation of the session, the one the
/// consent view rendered.
internal struct UserApproval: Equatable {
  internal let operationIdentifier: RappOperationIdentifier
  internal let approvedAtMilliseconds: UInt64

  internal init(for request: OperationRequest, approvedAtMilliseconds: UInt64) {
    self.operationIdentifier = request.operationIdentifier
    self.approvedAtMilliseconds = approvedAtMilliseconds
  }
}
