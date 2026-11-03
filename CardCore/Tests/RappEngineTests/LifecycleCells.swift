// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// What one lifecycle machine says for each state and event: transitions
/// unguarded and guarded, and fixed entries (ignored, or impossible without
/// a guard).
internal struct LifecycleCells {
  private var unguarded: [String: Int] = [:]
  private var guarded: [String: Int] = [:]
  private var fixed: [String: Int] = [:]

  internal init(_ machine: LifecycleMachine) {
    for rule in machine.transitions {
      for key in Self.keys(rule) {
        if rule.guards.isEmpty {
          unguarded[key, default: 0] += 1
        } else {
          guarded[key, default: 0] += 1
        }
      }
    }
    for entry in machine.ignored + machine.cannotHappen {
      for key in Self.keys(entry) {
        if entry.guards.isEmpty {
          fixed[key, default: 0] += 1
        } else {
          guarded[key, default: 0] += 1
        }
      }
    }
  }

  private static func keys(_ entry: LifecycleEntry) -> [String] {
    entry.from.flatMap { from in entry.event.map { event in "\(from)|\(event)" } }
  }

  /// One unguarded rule, or rules and guarded impossibilities told apart by
  /// guards, or one fixed entry.
  internal func hasOneAnswer(_ state: String, _ event: String) -> Bool {
    let key = "\(state)|\(event)"
    let rules = unguarded[key, default: 0]
    let told = guarded[key, default: 0]
    let entries = fixed[key, default: 0]
    if entries > 0 { return entries == 1 && rules + told == 0 }
    if rules > 0 { return rules == 1 && told == 0 }
    return told > 0
  }
}
