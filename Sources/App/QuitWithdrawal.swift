// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS) && REFINEID_REMOTE_CARD && REFINEID_STREAM_TRANSPORT

  import CoreFoundation
  import RappEngine

  /// Quitting while remote use is on: this computer's withdrawal (RAPP
  /// v26.10.29 §4.5 item 8, hierarchy specification §5.2).
  ///
  /// An open session closes with `service_withdrawn`, remote use stops
  /// with every pairing kept, and the quit waits for that close to leave,
  /// or for the bound to pass, before the app exits; the next launch
  /// restores remote use on while a pairing remains. A quit while the
  /// holder's click off is still forgetting waits first for its pairings to
  /// be destroyed (§4.6 item 6), which that click's own bound limits.
  @MainActor
  internal enum QuitWithdrawal {
    // MARK: Nested Types

    /// What a quit waits on before the app exits.
    internal struct Pending: Sendable {
      /// The destruction of the pairings a click off is forgetting.
      internal let forgetting: Task<RemoteUseForgetting.Outcome, Never>?

      /// The open session's withdrawal close.
      internal let closes: Task<Bool, Never>?
    }

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
    /// is on, keeping every pairing, and answers what the quit waits on:
    /// that close, and the destruction of a click off still forgetting;
    /// nil when nothing is left to wait for.
    internal static func begin(
      remoteUse: RemoteUseSwitch,
      registry: PersistentTokenRegistry
    ) -> Pending? {
      var closes: Task<Bool, Never>?
      if remoteUse.isOn {
        closes = registry.withdrawHolderSession()
        remoteUse.stop()
      }
      let forgetting = registry.pairingDestruction
      guard forgetting != nil || closes != nil else { return nil }
      return Pending(forgetting: forgetting, closes: closes)
    }

    /// Runs `done` once the pending forgetting has destroyed its pairings,
    /// and then once the pending close has finished or `limit` has passed,
    /// whichever comes first.
    ///
    /// `done` runs on the main run loop in its common modes, where AppKit
    /// waits for the answer to a quit, so it runs even while the main
    /// queue cannot; the destruction runs off the main thread.
    internal static func wait(
      for pending: Pending,
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
        if let forgetting = pending.forgetting {
          _ = await forgetting.value
        }
        guard let closes = pending.closes else {
          finish()
          return
        }
        Task.detached {
          _ = await closes.value
          finish()
        }
        try? await Task.sleep(for: limit)
        finish()
      }
    }
  }

#endif
