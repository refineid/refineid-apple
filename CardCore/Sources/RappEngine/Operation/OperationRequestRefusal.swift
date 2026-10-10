// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// A request that parsed as an envelope but names something this endpoint
/// cannot serve.
///
/// It is a semantic rejection answered with a result, not an authenticated
/// protocol violation (RAPP v26.10.9 §9.2), so it carries the reference the
/// result must echo.
internal struct OperationRequestRefusal: Error, Equatable {
  internal let reference: OperationReference
  internal let error: ResultError
}
