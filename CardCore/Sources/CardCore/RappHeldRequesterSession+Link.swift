// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if canImport(RappEngine)
  import Foundation
  import os

  extension RappHeldRequesterSession {
    /// The transport, owned apart from the session so the transport
    /// closures need no reference to it: a browser and the dialer it found,
    /// or a Bluetooth central.
    internal final class Link: @unchecked Sendable {
      private let browser = OSAllocatedUnfairLock<StreamRelayBrowser?>(initialState: nil)
      private let dialer = OSAllocatedUnfairLock<StreamRelaySession?>(initialState: nil)
      #if !os(macOS)
        private let central = OSAllocatedUnfairLock<RappBleGattCentral?>(initialState: nil)
      #endif

      internal func browse(with found: StreamRelayBrowser) {
        browser.withLock { $0 = found }
      }

      /// Installs the dialer unless one is already in place.
      internal func dial(with made: StreamRelaySession) -> Bool {
        dialer.withLock { installed in
          guard installed == nil else { return false }
          installed = made
          return true
        }
      }

      #if !os(macOS)
        internal func carry(over made: RappBleGattCentral) {
          central.withLock { $0 = made }
        }
      #endif

      internal func send(_ frame: Data) async throws {
        #if !os(macOS)
          if let link = central.withLock({ $0 }) {
            try await link.send(frame)
            return
          }
        #endif
        guard let link = dialer.withLock({ $0 }) else { throw RappRequesterClientError.transport }
        try await link.send(frame)
      }

      internal func cancel() {
        browser.withLock { $0 }?.cancel()
        dialer.withLock { $0 }?.cancel()
        #if !os(macOS)
          central.withLock { $0 }?.cancel()
        #endif
      }
    }
  }
#endif
