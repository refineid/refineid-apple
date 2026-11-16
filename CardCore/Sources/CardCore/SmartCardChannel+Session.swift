// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if canImport(CryptoTokenKit)
  import CryptoTokenKit
  import Foundation

  extension SmartCardChannel {
    /// Coordinates ownership of a session callback that arrives after its waiter gave up.
    ///
    /// `@unchecked Sendable` is sound because both flags are read and written only under
    /// `lock`, so whichever side runs second ends an abandoned session once.
    private final class SessionWait: @unchecked Sendable {
      private let lock = NSLock()
      private let backing: any SmartCardBacking
      private var waiterGaveUp = false
      private var sessionArrivedOpen = false

      init(backing: any SmartCardBacking) {
        self.backing = backing
      }

      func giveUp() {
        lock.lock()
        waiterGaveUp = true
        let orphaned = sessionArrivedOpen
        lock.unlock()
        guard orphaned else { return }
        backing.endSession()
      }

      func releaseIfAbandoned(opened: Bool) {
        lock.lock()
        sessionArrivedOpen = opened
        let abandoned = waiterGaveUp
        lock.unlock()
        guard opened, abandoned else { return }
        backing.endSession()
      }
    }

    /// An exclusive card session kept open past one lexical scope and ended at most once.
    ///
    /// `@unchecked Sendable` is sound because `channel` is immutable and `ended` is
    /// guarded by `lock`.
    public final class OpenSession: @unchecked Sendable {
      /// The channel operating inside this open session.
      public let channel: SmartCardChannel
      private let lock = NSLock()
      private var ended = false

      internal init(channel: SmartCardChannel) {
        self.channel = channel
      }

      /// Ends the exclusive session; subsequent calls do nothing.
      public func end() {
        lock.lock()
        let alreadyEnded = ended
        ended = true
        lock.unlock()
        guard !alreadyEnded else { return }
        channel.endSession()
      }

      deinit {
        end()
      }
    }

    /// Outcome of one protocol-offer session attempt.
    private enum SessionAttemptOutcome {
      case opened
      case refused((any Error)?)
      case timedOut
    }

    /// Interval between slot-departure checks while waiting for `beginSession`.
    private static let departureCheckMilliseconds = 250

    /// Opens an exclusive card session and leaves it open for the caller to end.
    public func beginSession() throws {
      let offers = SmartCardProtocolNegotiation.offers(answerToReset: backing.answerToReset)
      for (offset, protocols) in offers.enumerated() {
        switch attemptSession(offering: protocols) {
        case .opened:
          return
        case .timedOut:
          throw CardOperationError.sessionUnavailable
        case .refused(let failure):
          let hasNarrowerOffer = offset + 1 < offers.count
          guard
            hasNarrowerOffer,
            SmartCardProtocolNegotiation.retries(after: failure)
          else {
            throw failure ?? CardOperationError.sessionUnavailable
          }
          #if DEBUG
            recordTrace("session: retrying with a narrower protocol offer")
          #endif
        }
      }
      throw CardOperationError.sessionUnavailable
    }

    /// Ends an exclusive card session previously opened with ``beginSession()``.
    public func endSession() {
      #if DEBUG
        recordTrace("session: end channel=\(channelID)")
      #endif
      backing.endSession()
    }

    /// Opens an exclusive card session and returns an idempotent handle owning its lifetime.
    public func openSession() throws -> OpenSession {
      try beginSession()
      return OpenSession(channel: self)
    }

    /// Opens an exclusive card session, runs `body`, and ends the session synchronously.
    public func withSession<Value>(_ body: (Self) throws -> Value) throws -> Value {
      let session = try openSession()
      defer { session.end() }
      return try body(session.channel)
    }

    private func attemptSession(offering protocols: TKSmartCardProtocol) -> SessionAttemptOutcome {
      backing.allowedProtocols = protocols
      let began = Box(false)
      let failure = Box<(any Error)?>(nil)
      let wait = SessionWait(backing: backing)
      let semaphore = DispatchSemaphore(value: 0)
      #if DEBUG
        let started = ContinuousClock.now
      #endif
      backing.beginSession { opened, error in
        began.value = opened
        failure.value = error
        wait.releaseIfAbandoned(opened: opened)
        semaphore.signal()
      }
      guard awaitSession(semaphore) else {
        wait.giveUp()
        #if DEBUG
          recordTrace(
            "session: gave up waiting after "
              + TraceTiming.milliseconds(started.duration(to: ContinuousClock.now)) + " ms"
          )
        #endif
        return .timedOut
      }
      #if DEBUG
        let elapsed = TraceTiming.milliseconds(started.duration(to: ContinuousClock.now))
        if began.value {
          recordTrace("session: begin ok ms=\(elapsed) channel=\(channelID)")
        } else {
          recordTrace(
            "session: begin refused ms=\(elapsed) reason=\(String(describing: failure.value))"
          )
        }
      #endif
      return began.value ? .opened : .refused(failure.value)
    }

    private func awaitSession(_ semaphore: DispatchSemaphore) -> Bool {
      let deadline = DispatchTime.now() + policy.sessionWait
      while DispatchTime.now() < deadline {
        let slice = min(
          deadline,
          DispatchTime.now() + .milliseconds(Self.departureCheckMilliseconds)
        )
        if semaphore.wait(timeout: slice) == .success {
          return true
        }
        if cardHasLeft {
          #if DEBUG
            recordTrace("session: card left the slot while waiting")
          #endif
          return false
        }
      }
      return false
    }

    #if DEBUG
      @inline(__always)
      internal func recordExchange(
        request: Data,
        response: Data?,
        elapsed: Duration,
        progress: CardExchangeProgress
      ) {
        guard let sink = trace.exchange else { return }
        sink(
          ExchangeRecord(
            line: CardExchangeTrace.line(request: request, response: response, elapsed: elapsed),
            channelID: channelID,
            progressSnapshot: progress.snapshot()
          )
        )
      }

      @inline(__always)
      internal func recordTrace(_ message: @autoclosure () -> String) {
        guard let sink = trace.trace else { return }
        sink(message())
      }

      @inline(__always)
      internal func recordError(_ message: @autoclosure () -> String) {
        guard let sink = trace.error else { return }
        sink(message())
      }
    #endif
  }
#endif
