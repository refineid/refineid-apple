// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// A handshake token as written in a Noise message pattern.
internal enum NoiseToken {
  case ephemeral
  case ephemeralEphemeral
  case ephemeralStatic
  case presharedKey
  case staticEphemeral
  case staticKey
  case staticStatic
}
