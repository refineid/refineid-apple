// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// Why a drive step did not give the step the test expected.
internal struct DriveFailure: Error, CustomStringConvertible {
  internal let description: String
}
