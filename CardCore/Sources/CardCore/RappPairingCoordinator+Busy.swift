// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if canImport(RappEngine)
  import Foundation
  import RappEngine

  /// The custodian's bootstrap answer and its busy refusal (RAPP v26.10.29
  /// §4.2, Bootstrap Read Flow and "Busy Refusal").
  extension RappPairingCoordinator {
    /// Serves the custodian's bootstrap answer to a connection whose
    /// preamble arrived.
    ///
    /// The answer is computed first, so a connection answered busy moves no
    /// limiter; the connection-accept spacing is spent only when the offer
    /// is served. On BLE the answer is read from its characteristic, never
    /// sent as a frame, so a refused BLE link closes unanswered.
    internal func serveBootstrap(now: UInt64) async throws {
      guard servesOfferAsFrame else {
        guard preAuthentication.admit(nowMonotonicMs: now) else {
          await refuse(with: nil)
          return
        }
        state = .custodianAwaitingStepOne
        return
      }
      let answer = try bridge.bootstrapBytes(nowMonotonicMs: now)
      guard (try? rappPairingBusyRetryAfterMs(answer)) == nil else {
        await refuse(with: answer)
        return
      }
      guard preAuthentication.admit(nowMonotonicMs: now) else {
        await refuse(
          with: try bridge.busyBytes(
            nowMonotonicMs: now, spacingWaitMs: preAuthentication.waitMs(nowMonotonicMs: now)))
        return
      }
      state = .custodianAwaitingStepOne
      try await transport.send(answer)
    }

    /// Answers a connection the custodian cannot admit, and ends it.
    ///
    /// `busy` goes first when given; the offer stays (§4.2, "Busy Refusal").
    /// A transport that outlives the connection keeps serving under the same
    /// published name; one that cannot is closed and reported for replacement.
    internal func refuse(with busy: Data?) async {
      state = .offer
      if let busy {
        if await transport.endConnection(answering: busy) { return }
        try? await transport.send(busy)
      }
      await transport.close()
      continuation.yield(.offerRestored)
    }
  }
#endif
