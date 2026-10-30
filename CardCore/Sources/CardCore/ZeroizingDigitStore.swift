// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

/// Backing storage for credential digits, overwritten with zeros when the
/// last owner releases it.
///
/// Zeroization in Swift is best effort: copies made before the value reached
/// this store - for example the String the system PIN sheet delivered - are
/// outside its reach. What this store guarantees is that the digits it owns
/// do not outlive their use.
///
/// `@unchecked Sendable` is sound: `bytes` is set once at init (before the
/// store is shared) and mutated only in `deinit` (no concurrent access at
/// that point); every owner is either a noncopyable value with unique
/// ownership (`Pin1`, `Pin1Transmission`) or holds it behind a mutex
/// (`Pin1Memory`), so it is never mutated while shared.
internal final class ZeroizingDigitStore: @unchecked Sendable {
  /// The raw digit bytes.
  ///
  /// Internal so only the module's own boundary code (fingerprinting, the
  /// future transport) can read them; this class is the sanctioned
  /// bytes-to-type boundary in the lint exception register.
  internal private(set) var bytes: [UInt8]

  internal init(bytes: [UInt8]) {
    self.bytes = bytes
  }

  deinit {
    for index in bytes.indices {
      bytes[index] = 0
    }
  }
}
