// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// An `operation_id` (RAPP v26.10.29 §7.1 `bstr .size 16`, §8.1 item 1):
/// fresh random bytes the requester draws for each operation, used once per
/// session.
///
/// The value means only its identity, so it is compared and hashed, never
/// read; the wire form is re-serialized inside the engine.
public struct RappOperationIdentifier: Hashable, Sendable {
  /// Byte length the specification fixes.
  internal static let byteCount = 16

  internal let bytes: Data

  /// An identifier from 16 platform random bytes, or from the wire; nil for
  /// any other length.
  public init?(_ bytes: Data) {
    guard bytes.count == Self.byteCount else { return nil }
    self.bytes = bytes
  }
}
