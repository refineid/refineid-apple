// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// An exclusive card transport that can be explicitly ended when released.
public protocol HeldCardChannel: CardChannel, Sendable {
  /// Ends the exclusive card session.
  func endSession()
}
