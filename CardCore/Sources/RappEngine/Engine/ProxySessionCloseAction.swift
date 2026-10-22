// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// What happens to the live operation when its session closes (RAPP
/// v26.10.22 §8.1 item 3).
internal enum ProxySessionCloseAction: Equatable {
  /// The card command runs to the card's answer, which is discarded.
  case continueCardExchange(operationIdentifier: RappOperationIdentifier)
  /// The card was not commanded; the operation is dropped.
  case dropped(operationIdentifier: RappOperationIdentifier)
}
