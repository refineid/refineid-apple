// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// Whether the custodian's device has its lock screen up.
@MainActor
internal protocol CustodianLockState {
  var isLocked: Bool { get }
}
