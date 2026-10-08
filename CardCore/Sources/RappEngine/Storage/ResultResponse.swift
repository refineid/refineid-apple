// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// The `response` map of a completed result, as the wire carries it.
///
/// A present but empty map and an absent one are different results, so the
/// map travels inside this value rather than as an optional collection.
internal struct ResultResponse: Equatable {
  internal var fields: [String: WireValue]
}
