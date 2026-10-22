// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// The thirteen registered envelope discriminants (RAPP v26.10.22 §7.1).
internal enum MessageType: String, CaseIterable {
  case cardStatus = "card.status"
  case error = "error"
  case livenessPing = "liveness.ping"
  case livenessPong = "liveness.pong"
  case operationProgress = "operation.progress"
  case operationRequest = "operation.request"
  case operationResult = "operation.result"
  case pairingAbort = "pairing.abort"
  case pairingConfirm = "pairing.confirm"
  case pairingHello = "pairing.hello"
  case pairingStored = "pairing.stored"
  case sessionClose = "session.close"
  case sessionReady = "session.ready"
}
