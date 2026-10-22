// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// A request that parsed as an envelope but names something this endpoint
/// cannot serve.
///
/// It is answered with a rejected result, not a session close (RAPP
/// v26.10.21 §10.1 item 3), so it carries the identifier the result names.
internal struct OperationRequestRefusal: Error, Equatable {
  internal let operationIdentifier: RappOperationIdentifier
  internal let error: ResultError
}
