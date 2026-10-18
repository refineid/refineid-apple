// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if canImport(MultipeerConnectivity) && canImport(RappEngine) && REFINEID_STREAM_TRANSPORT
  import Foundation
  import os

  extension RappHeldRequesterSession {
    /// The browser and dialer, owned apart from the session so the
    /// transport closures need no reference to it.
    internal final class Link: @unchecked Sendable {
      private let lock = OSAllocatedUnfairLock<(StreamRelayBrowser?, StreamRelaySession?)>(
        initialState: (nil, nil))

      internal func browse(with browser: StreamRelayBrowser) {
        lock.withLock { $0.0 = browser }
      }

      /// Installs the dialer unless one is already in place.
      internal func dial(with dialer: StreamRelaySession) -> Bool {
        lock.withLock { link in
          guard link.1 == nil else { return false }
          link.1 = dialer
          return true
        }
      }

      internal func send(_ frame: Data) async throws {
        guard let dialer = lock.withLock({ $0.1 }) else {
          throw RappRequesterClientError.transport
        }
        try await dialer.send(frame)
      }

      internal func cancel() {
        let (browser, dialer) = lock.withLock { $0 }
        browser?.cancel()
        dialer?.cancel()
      }
    }
  }
#endif
