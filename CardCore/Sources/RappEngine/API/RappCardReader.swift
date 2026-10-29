// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// Whether a contact card reader is connected to the custodian (RAPP
/// v26.10.29 §8.4 item 1).
public enum RappCardReader: Equatable, Sendable {
  /// No contact card reader is connected, as on a custodian that reads
  /// cards only over NFC.
  case absent
  /// A contact card reader is connected: built in, or attached to a
  /// Universal Serial Bus (USB) or Lightning port.
  case attached
}
