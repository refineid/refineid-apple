// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// One rule or entry of a lifecycle machine, as its flow-style line reads.
internal struct LifecycleEntry {
  internal var from: [String] = []
  internal var event: [String] = []
  internal var guards: [String] = []
  internal var role: String?
  internal var destination: String?
  internal var actions: [String] = []
  internal var reason: String?
}
