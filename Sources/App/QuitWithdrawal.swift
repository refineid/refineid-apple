// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS) && REFINEID_REMOTE_CARD && REFINEID_STREAM_TRANSPORT

  import CoreFoundation
  import RappEngine

  /// Quitting while remote use is on: this computer's withdrawal (RAPP
  /// v26.10.22 §4.5 item 8, hierarchy specification §5.2).
  ///
  /// An open session closes with `service_withdrawn`, remote use stops
  /// with every pairing kept, and the quit waits for that close to leave,
  /// or for the bound to pass, before the app exits; the next launch
  /// restores remote use on while a pairing remains. The holder's click off
  /// waits on its `pairing_revoked` closes the same way (§4.6 item 6).
  @MainActor
  internal enum QuitWithdrawal {
    // MARK: Nested Types

    /// Runs its action the first time it is asked to, and never again.
    @MainActor
    private final class Once {
      private var action: (@MainActor () -> Void)?

      init(_ action: @escaping @MainActor () -> Void) {
        self.action = action
      }

      func run() {
        let pending = action
        action = nil
        pending?()
      }
    }

    // MARK: Static Properties

    /// How long quitting waits for the withdrawal close to leave, and the
    /// holder's click off for the revocation close.
    internal static let bound = Duration.milliseconds(Int64(rappQuitWithdrawalBoundMs()))

    // MARK: Static Functions

    /// Withdraws the session of `registry` and stops `remoteUse`, when it
    /// is on, keeping every pairing, and answers the session's close; nil
    /// when nothing is left to wait for.
    internal static func begin(
      remoteUse: RemoteUseSwitch,
      registry: PersistentTokenRegistry
    ) -> Task<Bool, Never>? {
      guard remoteUse.isOn else { return nil }
      let closes = registry.withdrawHolderSession()
      remoteUse.stop()
      return closes
    }

    /// Runs `done` once `closes` has finished or `limit` has passed,
    /// whichever comes first.
    ///
    /// `done` runs on the main run loop in its common modes, where AppKit
    /// waits for the answer to a quit, so it runs even while the main
    /// queue cannot.
    internal static func wait(
      for closes: Task<Bool, Never>,
      atMost limit: Duration,
      then done: @escaping @MainActor () -> Void
    ) {
      let once = Once(done)
      let finish: @Sendable () -> Void = {
        let mainLoop = CFRunLoopGetMain()
        CFRunLoopPerformBlock(mainLoop, CFRunLoopMode.commonModes.rawValue) {
          MainActor.assumeIsolated { once.run() }
        }
        CFRunLoopWakeUp(mainLoop)
      }
      Task.detached {
        _ = await closes.value
        finish()
      }
      Task.detached {
        try? await Task.sleep(for: limit)
        finish()
      }
    }
  }

#endif
