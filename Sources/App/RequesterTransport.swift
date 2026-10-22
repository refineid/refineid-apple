// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// The transports a requester reaches the paired phone over.
internal enum RequesterTransport: Equatable, Sendable {
  case bluetooth
  case stream
}
