// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

@testable import RefineID

internal struct ParsedGrammar {
  internal let initialState: CardSetupStateMachine.State
  internal let states: Set<CardSetupStateMachine.State>
  internal let transitions: [CardSetupStateMachine.Transition]
}
