// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// The session's operation that ended when the session closed (RAPP
/// v26.10.21 §8.1 item 3).
public enum RappEndedOperation: Equatable, Sendable {
  /// The custodian's card command runs to the card's answer, which is
  /// discarded.
  case cardExchangeContinues(RappOperationIdentifier)
  /// The card was not commanded; the operation is dropped.
  case dropped(RappOperationIdentifier)
}
