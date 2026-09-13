// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// The registered envelope discriminants.
internal enum MessageType: String, CaseIterable {
  case error = "error"
  case livenessPing = "liveness.ping"
  case livenessPong = "liveness.pong"
  case operationCancel = "operation.cancel"
  case operationCommit = "operation.commit"
  case operationPrepared = "operation.prepared"
  case operationProgress = "operation.progress"
  case operationRequest = "operation.request"
  case operationResult = "operation.result"
  case operationResultAck = "operation.result_ack"
  case operationStatus = "operation.status"
  case operationStatusRequest = "operation.status_request"
  case pairingAbort = "pairing.abort"
  case pairingConfirm = "pairing.confirm"
  case pairingHello = "pairing.hello"
  case sessionClose = "session.close"
  case sessionReady = "session.ready"
}
