// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// One TXT key and value, in the order a record publishes them.
public struct RappTxtEntry: Equatable, Sendable {
  /// The key, matched without regard to ASCII case.
  public var key: String
  /// The value, matched exactly.
  public var value: String

  /// An entry of `key` and `value`.
  public init(key: String, value: String) {
    self.key = key
    self.value = value
  }

  internal init(_ entry: (String, String)) {
    self.init(key: entry.0, value: entry.1)
  }
}
