// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CardCore
import CryptoTokenKit
import Foundation

/// Adapts a `TKSmartCard` to CardCore's synchronous `CardChannel` for the
/// app's status and diagnostic reads, and opens the exclusive session.
///
/// Same shape as the extension's adapter: each APDU is driven with a
/// completion handler plus a `DispatchSemaphore` (the reply fires on
/// `TKSmartCard`'s own queue), never Swift concurrency. Callers run it on
/// a background GCD queue so the blocking wait never touches the
/// cooperative pool or the main thread.
internal struct SmartCardChannel: CardChannel {
  /// A transport failure before the card produced a protocol response.
  internal enum TransportError: Error, Equatable, Sendable {
    /// CryptoTokenKit did not complete one APDU within the budget.
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

  /// How long one APDU may wait, set by the transport that owns the field.
  internal enum ResponseWait: Sendable, Equatable {
    case nearField
    case reader
  }

  /// How long to wait for whoever else has the card.
  ///
  /// Shorter than the driver's budget on purpose. This is the status
  /// screen: a card that is busy signing for Safari should make a row
  /// say so, not make the app stop answering.
  private static let sessionWaitSeconds: Int = 4

  /// The same budget, in the units `DispatchSemaphore` wants.
  private static let sessionWaitBudget: DispatchTimeInterval = .seconds(sessionWaitSeconds)

  /// Maximum time allowed for an individual APDU response on near-field.
  internal static let nearFieldResponseSeconds: Int = 10

  /// The reader budget: room for the card's slowest legal answer.
  ///
  /// Accommodates progressive CAN-PACE delays (up to 45-50+ seconds) and
  /// cryptographic calculations on continuous-power desktop PC/SC readers.
  internal static let readerResponseSeconds: Int = 60

  /// A reader hands back exactly the bytes the card produced, so a
  /// chunked read may ask for the plain chunk.
  internal var readChunkLength: ReadChunkLength {
    .plain
  }

  private let smartCard: TKSmartCard
  private let responseBudget: DispatchTimeInterval

  internal init(_ smartCard: TKSmartCard, waits: ResponseWait) {
    self.smartCard = smartCard
    switch waits {
    case .nearField:
      self.responseBudget = .seconds(Self.nearFieldResponseSeconds)
    case .reader:
      self.responseBudget = .seconds(Self.readerResponseSeconds)
    }
  }

  internal init(_ smartCard: TKSmartCard) {
    self.init(
      smartCard,
      waits: Self.defaultWait(forSlotNamed: smartCard.slot.name))
  }

  /// Determines the appropriate wait policy for a given smart card slot name.
  internal static func defaultWait(forSlotNamed name: String) -> ResponseWait {
    CardTransport.transport(forSlotNamed: name) == .nearField ? .nearField : .reader
  }

  /// Sends one command and waits for the card, tracing the exchange.
  ///
  /// The app's own card work -- priming, above all -- was invisible while
  /// only the extensions were traced, which meant a failed hold could be
  /// read about afterwards but never diagnosed. Debug records the complete
  /// command and response through ``CardExchangeTrace``; ``AppTrace`` compiles
  /// the entire operation away from shipped builds.
  internal func transmit(_ payload: Data) throws -> Data {
    let reply = Box<Data?>(nil)
    let transportError = Box<Error?>(nil)
    let semaphore = DispatchSemaphore(value: 0)
    let started = ContinuousClock.now
    smartCard.transmit(payload) { response, error in
      reply.value = response
      transportError.value = error
      semaphore.signal()
    }
    guard semaphore.wait(timeout: .now() + responseBudget) == .success else {
      let elapsed = started.duration(to: ContinuousClock.now)
      AppTrace.append(
        CardExchangeTrace.line(request: payload, response: nil, elapsed: elapsed)
      )
      throw TransportError.responseTimedOut
    }
    let elapsed = started.duration(to: ContinuousClock.now)
    AppTrace.append(
      CardExchangeTrace.line(request: payload, response: reply.value, elapsed: elapsed)
    )
    guard let response = reply.value else {
      if let callbackError = transportError.value {
        throw callbackError
      }
      throw CardOperationError.malformedResponse
    }
    return response
  }

  /// Opens an exclusive session, runs `body`, and ends it - synchronously.
  internal func withSession<T>(_ body: (Self) throws -> T) throws -> T {
    let offers = SmartCardProtocolNegotiation.offers(
      answerToReset: smartCard.slot.atr?.bytes)
    for (offset, protocols) in offers.enumerated() {
      smartCard.allowedProtocols = protocols
      let began = Box(false)
      let failure = Box<Error?>(nil)
      let wait = SessionWait(card: smartCard)
      let semaphore = DispatchSemaphore(value: 0)
      smartCard.beginSession { opened, error in
        began.value = opened
        failure.value = error
        wait.releaseIfAbandoned(opened: opened)
        semaphore.signal()
      }
      guard semaphore.wait(timeout: .now() + Self.sessionWaitBudget) == .success else {
        wait.giveUp()
        throw CardOperationError.sessionUnavailable
      }
      if began.value {
        defer { smartCard.endSession() }
        return try body(self)
      }
      let hasNarrowerOffer = offset + 1 < offers.count
      guard
        hasNarrowerOffer,
        SmartCardProtocolNegotiation.retries(after: failure.value)
      else {
        throw failure.value ?? CardOperationError.sessionUnavailable
      }
    }
    throw CardOperationError.sessionUnavailable
  }
}
