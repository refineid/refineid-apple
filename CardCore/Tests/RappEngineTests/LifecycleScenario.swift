// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// One walk through a machine.
internal struct LifecycleScenario: Decodable {
  internal let name: String
  internal let machine: String
  internal let role: String
  internal let start: String
  internal let steps: [LifecycleStep]
}
