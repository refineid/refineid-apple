// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// One event of a walk and its expected answer.
internal struct LifecycleStep: Decodable {
  private enum CodingKeys: String, CodingKey {
    case event = "event"
    case guards = "guards"
    case outcome = "outcome"
    case state = "state"
    case actions = "actions"
  }

  /// The ordered actions a transition names.
  internal struct Actions: Decodable, Equatable {
    internal let names: [String]

    internal init(from decoder: any Decoder) throws {
      names = try decoder.singleValueContainer().decode([String].self)
    }
  }

  internal let event: String
  /// The guards that hold; none when the step names none.
  internal let guards: [String]
  internal let outcome: String
  /// The state after a transition; nil for any other outcome.
  internal let state: String?
  /// The ordered actions of a transition; nil for any other outcome.
  internal let actions: Actions?

  internal init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    event = try container.decode(String.self, forKey: .event)
    guards = try container.decodeIfPresent([String].self, forKey: .guards) ?? []
    outcome = try container.decode(String.self, forKey: .outcome)
    state = try container.decodeIfPresent(String.self, forKey: .state)
    actions = try container.decodeIfPresent(Actions.self, forKey: .actions)
  }
}
