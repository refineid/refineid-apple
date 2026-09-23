// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CardCore
import CryptoTokenKit
import Foundation

/// Adapts a `TKSmartCard` to CardCore's synchronous `CardChannel`, and
/// opens the exclusive session the card work runs inside.
///
/// The CTK token/session entry points are synchronous and run on ctkd's
/// own threads; the card is a synchronous blocking device. So each APDU is
/// driven with a completion handler plus a `DispatchSemaphore` - the reply
/// fires on `TKSmartCard`'s own queue and signals the wait - and never
/// through Swift concurrency. Blocking the ctkd thread this way is safe
/// and is what the proven reference does; an async/await bridge on that
/// thread is not (it hangs the sign, looping the PIN prompt).
internal struct SmartCardChannel: CardChannel {
  /// A transport failure before the card produced a protocol response.
  internal enum TransportError: Error, Equatable, Sendable {
    /// CryptoTokenKit did not complete one APDU within the field budget.
    case responseTimedOut
  }

  /// Carries a value across the semaphore boundary; sound because the
  /// semaphore serialises the write before the wait returns.
  private final class Box<Value>: @unchecked Sendable {
    var value: Value

    init(_ value: Value) {
      self.value = value
    }
  }

  /// Decides which side is responsible for a session that arrives after
  /// the waiter has given up, and hands it back when that is nobody.
  ///
  /// Both sides need the same answer and they run on different threads:
  /// the waiter times out, the callback fires a moment later, and if
  /// neither claims the session it stays open forever -- the card held
  /// by a process no longer interested in it, which is precisely the jam
  /// this timeout exists to end.
  ///
  /// `@unchecked Sendable` is the audit, not a shrug: both flags are only
  /// read and written under the lock, and whichever side runs second sees
  /// the other's flag, so exactly one of them ends an abandoned session.
  private final class SessionWait: @unchecked Sendable {
    private let lock = NSLock()
    private let card: TKSmartCard
    private var waiterGaveUp = false
    private var sessionArrivedOpen = false

    init(card: TKSmartCard) {
      self.card = card
    }

    /// Called by the waiter when its budget runs out; ends a session
    /// whose callback has already delivered it open.
    func giveUp() {
      lock.lock()
      waiterGaveUp = true
      let orphaned = sessionArrivedOpen
      lock.unlock()
      guard orphaned else { return }
      card.endSession()
    }

    /// Called by the callback: ends a session nobody is waiting for.
    func releaseIfAbandoned(opened: Bool) {
      lock.lock()
      sessionArrivedOpen = opened
      let abandoned = waiterGaveUp
      lock.unlock()
      guard opened, abandoned else { return }
      card.endSession()
    }
  }

  /// How long one APDU may wait, set by the transport that owns the
  /// field.
  ///
  /// The phone's system field ends about two seconds after the mint, so
  /// waiting longer there cannot be repaid: once one command has taken
  /// two seconds, the window is already gone. A powered reader holds
  /// the card for as long as the work takes, and the card's PACE
  /// arithmetic together with the reader's waiting-time extensions can
  /// legitimately exceed the phone budget -- a reader exchange gets
  /// room instead of a guillotine, which was tearing the field and
  /// blinking the reader in a loop.
  internal enum ResponseWait {
    case nearField
    case reader
  }

  /// How long to wait for whoever else has the card.
  ///
  /// The wait used to be unbounded, and an unbounded wait is how one
  /// stuck process takes the card away from everything else: the app
  /// froze rather than saying the card was busy. Eight seconds is far
  /// longer than any operation here -- a handshake is about a second, a
  /// signature about the same -- so a legitimate queue still clears,
  /// while a holder that is never letting go becomes an error instead of
  /// a hang.
  private static let sessionWaitSeconds: Int = 10

  /// The same budget, in the units `DispatchSemaphore` wants.
  private static let sessionWaitBudget: DispatchTimeInterval = .seconds(sessionWaitSeconds)

  /// Maximum time allowed for an individual APDU response on near-field.
  ///
  /// On-card private key operations like RSA-3072 modular exponentiation
  /// require several seconds on low-power card chips. The card issues
  /// ISO 14443-4 WTX (waiting time extension) frames while calculating.
  private static let nearFieldResponseSeconds: Int = 10

  /// The reader budget: room for the card's slowest legal answer.
  private static let readerResponseSeconds: Int = 10

  /// Shift from a status word to its high byte.
  private static let statusWordByteShift: Int = 8

  /// A reader hands back exactly the bytes the card produced, so a
  /// chunked read may ask for the plain chunk.
  internal var readChunkLength: ReadChunkLength {
    .plain
  }

  private let smartCard: TKSmartCard

  /// The response budget the constructing transport chose.
  private let responseBudget: DispatchTimeInterval

  internal init(_ smartCard: TKSmartCard, waits: ResponseWait) {
    self.smartCard = smartCard
    self.responseBudget =
      switch waits {
      case .nearField:
        .seconds(Self.nearFieldResponseSeconds)

      case .reader:
        .seconds(Self.readerResponseSeconds)
      }
  }

  /// Sends one APDU, and records what it was and what it cost.
  ///
  /// This is the one place every exchange the extension makes passes
  /// through -- plain and secure-messaged alike, since the secure channel
  /// wraps this one -- so it is where the trace is taken. The recorded
  /// line contains instruction, status, and timing from ``CardExchangeTrace``.
  /// ``TokenLog`` compiles the trace sink out of shipped builds.
  internal func transmit(_ payload: Data) throws -> Data {
    let reply = Box<Data?>(nil)
    let transportError = Box<Error?>(nil)
    let semaphore = DispatchSemaphore(value: 0)
    let started = ContinuousClock.now
    startTransmit(
      payload,
      reply: reply,
      transportError: transportError,
      semaphore: semaphore)
    guard semaphore.wait(timeout: .now() + responseBudget) == .success else {
      let elapsed = started.duration(to: ContinuousClock.now)
      TokenLog.trace(
        CardExchangeTrace.line(request: payload, response: nil, elapsed: elapsed)
      )
      TokenLog.trace("apdu: response timed out")
      throw TransportError.responseTimedOut
    }
    let elapsed = started.duration(to: ContinuousClock.now)
    TokenLog.trace(
      CardExchangeTrace.line(request: payload, response: reply.value, elapsed: elapsed)
    )
    guard let response = reply.value else {
      if let callbackError = transportError.value {
        TokenLog.error("apdu: transmit failed: \(callbackError)")
        throw callbackError
      }
      throw CardOperationError.malformedResponse
    }
    return response
  }

  /// Sends the payload directly over the card transport.
  private func startTransmit(
    _ payload: Data,
    reply: Box<Data?>,
    transportError: Box<Error?>,
    semaphore: DispatchSemaphore
  ) {
    smartCard.transmit(payload) { response, error in
      reply.value = response
      transportError.value = error
      semaphore.signal()
    }
  }

  /// Opens an exclusive session and LEAVES IT OPEN, for the caller to end.
  ///
  /// A session is not optional anywhere: `getSmartCard()` does not
  /// guarantee an open one, `transmit` is legal only inside one, and a
  /// sessionless transmit on the built-in contactless slot is parked by
  /// `ctkd` forever - no error, no timeout. `beginSession`'s callback
  /// fires on `TKSmartCard`'s own queue, so the semaphore never
  /// deadlocks.
  ///
  /// The caller owns the session from here and must end it. Most callers
  /// want ``withSession(_:)``; the exception is the contactless mint,
  /// which keeps its session alive for the signature that follows (see
  /// ``HeldCardSession``).
  internal func beginSession() throws {
    let offers = SmartCardProtocolNegotiation.offers(
      answerToReset: smartCard.slot.atr?.bytes)
    for (offset, protocols) in offers.enumerated() {
      smartCard.allowedProtocols = protocols
      let began = Box(false)
      let failure = Box<Error?>(nil)
      let wait = SessionWait(card: smartCard)
      let semaphore = DispatchSemaphore(value: 0)
      let started = ContinuousClock.now
      smartCard.beginSession { opened, error in
        began.value = opened
        failure.value = error
        wait.releaseIfAbandoned(opened: opened)
        semaphore.signal()
      }
      guard semaphore.wait(timeout: .now() + Self.sessionWaitBudget) == .success else {
        wait.giveUp()
        TokenLog.trace(
          "session: gave up waiting after "
            + TraceTiming.milliseconds(started.duration(to: ContinuousClock.now)) + " ms"
        )
        throw CardOperationError.sessionUnavailable
      }
      let elapsed = TraceTiming.milliseconds(started.duration(to: ContinuousClock.now))
      if began.value {
        TokenLog.trace("session: begin ok ms=\(elapsed)")
        return
      }
      // The failure is the diagnosis here: TKError -7 on the built-in
      // contactless slot means the field the mint held has already ended.
      TokenLog.trace(
        "session: begin refused ms=\(elapsed) reason=\(String(describing: failure.value))"
      )
      let hasNarrowerOffer = offset + 1 < offers.count
      guard
        hasNarrowerOffer,
        SmartCardProtocolNegotiation.retries(after: failure.value)
      else {
        throw failure.value ?? CardOperationError.sessionUnavailable
      }
      TokenLog.trace("session: retrying with a narrower protocol offer")
    }
    throw CardOperationError.sessionUnavailable
  }

  /// Ends a session opened with ``beginSession()``.
  internal func endSession() {
    TokenLog.trace("session: end")
    smartCard.endSession()
  }

  /// Opens an exclusive session, runs `body`, and ends the session - all
  /// synchronously.
  ///
  /// Required on both the createToken and the contact sign paths (the
  /// reference opens a session on every sign, proven by its success
  /// trace).
  internal func withSession<T>(_ body: (Self) throws -> T) throws -> T {
    try beginSession()
    defer { endSession() }
    return try body(self)
  }
}
