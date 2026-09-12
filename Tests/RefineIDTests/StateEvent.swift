// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

@testable import RefineID

internal struct StateEvent: Hashable {
  internal let state: CardSetupStateMachine.State
  internal let event: CardSetupStateMachine.Event
}
