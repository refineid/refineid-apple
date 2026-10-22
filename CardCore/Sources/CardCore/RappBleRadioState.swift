// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// The radio state names a trace needs, apart from Core Bluetooth.
public enum RappBleRadioState: Sendable, Equatable {
  case poweredOff
  case poweredOn
  case resetting
  case unauthorized
  case unknown
  case unsupported
}
