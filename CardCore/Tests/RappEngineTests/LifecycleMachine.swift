// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// One machine of the formal model, read for its lifecycle shape: role,
/// initial state, states, events, transitions, ignored and impossible
/// entries, and presentation (RAPP v26.11.2 §4.7).
internal struct LifecycleMachine {
  internal var role: String?
  internal var initial = ""
  internal var states: [String] = []
  internal var events: [String] = []
  internal var transitions: [LifecycleEntry] = []
  internal var ignored: [LifecycleEntry] = []
  internal var cannotHappen: [LifecycleEntry] = []
  internal var presentation: [String: String] = [:]
}
