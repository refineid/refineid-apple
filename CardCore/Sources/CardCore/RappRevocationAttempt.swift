// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if canImport(RappEngine)
  import Foundation
  import RappEngine

  /// A requester's one bounded attempt to tell its custodian that its user
  /// forgot the pairing while no session to it was open (RAPP v26.11.2 §4.6
  /// item 6).
  ///
  /// The attempt opens at most one connection, within
  /// ``rappRevocationAttemptBoundMs()`` of the forget: it browses for the
  /// custodian's session record, dials the first instance found for the
  /// pairing, completes the handshake and sends the `pairing_revoked` close
  /// as its first message, then waits for the echo until the bound ends. It
  /// offers no identity and starts no operation; the caller destroys the
  /// key once it returns, whatever it answers.
  public enum RappRevocationAttempt {
    /// The attempt's answer, settled once by whichever comes first: the
    /// session's end or the bound.
    private final class Outcome: @unchecked Sendable {
      private let lock = NSLock()
      private var isSettled = false
      private var answer = false
      private var waiting: CheckedContinuation<Bool, Never>?

      fileprivate var delivered: Bool {
        get async {
          await withCheckedContinuation { continuation in
            lock.lock()
            guard isSettled else {
              waiting = continuation
              lock.unlock()
              return
            }
            let settled = answer
            lock.unlock()
            continuation.resume(returning: settled)
          }
        }
      }

      fileprivate func settle(delivered: Bool) {
        lock.lock()
        guard !isSettled else {
          lock.unlock()
          return
        }
        isSettled = true
        answer = delivered
        let continuation = waiting
        waiting = nil
        lock.unlock()
        continuation?.resume(returning: delivered)
      }
    }

    private static let millisecondsPerSecond: Int64 = 1_000
    private static let attosecondsPerMillisecond: Int64 = 1_000_000_000_000_000

    /// Runs the attempt for `pair`, a record already forgotten, until
    /// `deadline`; answers whether its close was sent.
    public static func deliver(_ pair: RappPairRecord, until deadline: ContinuousClock.Instant)
      async -> Bool
    {
      let remaining = deadline - .now
      guard remaining > .zero, pair.metadata().forgottenAtMs != nil else { return false }
      let parts = remaining.components
      let milliseconds = UInt64(
        parts.seconds * millisecondsPerSecond + parts.attoseconds / attosecondsPerMillisecond)
      let outcome = Outcome()
      let session = RappHeldRequesterSession(
        pair: pair, route: .stream, policy: .interactive,
        closeEchoBoundMilliseconds: milliseconds
      ) { report in
        guard case .closed(let reason) = report else { return }
        outcome.settle(delivered: reason == .handshake(.revocationNoticeDelivered))
      }
      session.start()
      let bound = Task {
        try? await Task.sleep(until: deadline, clock: .continuous)
        outcome.settle(delivered: false)
        session.close()
      }
      let delivered = await outcome.delivered
      bound.cancel()
      return delivered
    }
  }
#endif
