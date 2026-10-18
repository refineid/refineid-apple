// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// The credential state of one session, written by the operation on its
/// own thread the moment the card answers and read by the next request;
/// the lock makes each write visible before the write returns.
internal final class CredentialSessionBox: @unchecked Sendable {
  private let lock = NSLock()
  private var state = CredentialSessionState()

  /// A copy of the state now.
  internal func read() -> CredentialSessionState {
    lock.lock()
    defer { lock.unlock() }
    return state
  }

  /// Changes the state before returning.
  internal func mutate(_ change: (inout CredentialSessionState) -> Void) {
    lock.lock()
    change(&state)
    lock.unlock()
  }
}
