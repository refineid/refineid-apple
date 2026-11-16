// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS) && FEATURE_SCS
  import Foundation
  import os

  /// Lifetime handle tying one in-flight SCS PIN modal to its
  /// connection and server lifecycle.
  internal final class ScsPromptCancellationToken: Sendable {
    private struct State {
      var cancelled = false
      var abortHandler: (@Sendable () -> Void)?
    }

    private let state = OSAllocatedUnfairLock(initialState: State())

    internal var isCancelled: Bool {
      state.withLock { $0.cancelled }
    }

    /// Registers `abort` while a modal prompt is open; runs immediately
    /// when the token was already cancelled.
    internal func installAbort(_ abort: @escaping @Sendable () -> Void) -> Bool {
      let alreadyCancelled = state.withLock { current -> Bool in
        if current.cancelled {
          return true
        }
        current.abortHandler = abort
        return false
      }
      if alreadyCancelled {
        abort()
        return false
      }
      return true
    }

    /// Detaches the modal abort handler once `runModal()` returns.
    internal func clearAbort() {
      state.withLock { current in
        current.abortHandler = nil
      }
    }

    /// Marks the request cancelled and aborts any open modal prompt.
    internal func cancel() {
      let handler = state.withLock { current -> (@Sendable () -> Void)? in
        guard !current.cancelled else { return nil }
        current.cancelled = true
        let active = current.abortHandler
        current.abortHandler = nil
        return active
      }
      handler?()
    }
  }
#endif
