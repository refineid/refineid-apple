// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// The holder's approval of one operation of the session, the one the PIN
/// prompt rendered, or the PIN the custodian already holds (RAPP v26.10.29
/// §8.2 item 3).
internal struct UserApproval: Equatable {
  internal let operationIdentifier: RappOperationIdentifier
  internal let approvedAtMilliseconds: UInt64

  internal init(for request: OperationRequest, approvedAtMilliseconds: UInt64) {
    self.operationIdentifier = request.operationIdentifier
    self.approvedAtMilliseconds = approvedAtMilliseconds
  }
}
