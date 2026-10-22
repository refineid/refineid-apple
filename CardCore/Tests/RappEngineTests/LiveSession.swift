// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

@testable import RappEngine

/// Both sides of one established session.
internal struct LiveSession {
  internal let requester: RappOperationBridge
  internal let custodian: RappOperationBridge
}
