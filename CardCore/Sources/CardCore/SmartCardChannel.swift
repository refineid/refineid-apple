// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if canImport(CryptoTokenKit)
  import CryptoTokenKit
  import Foundation

  /// Adapts a `TKSmartCard` to synchronous ``CardChannel`` and ``HeldCardChannel`` operations.
  ///
  /// Each APDU and session transition bridges `TKSmartCard`'s callback queue through a
  /// `DispatchSemaphore`, never Swift concurrency, so callers on `ctkd` or background
  /// GCD queues block cleanly without touching the cooperative pool. Card sessions are
  /// half-duplex: callers serialize ``transmit(_:)`` within one exclusive session, and
  /// struct copies share ``channelID`` and ``exchangeProgressSnapshot`` for trace correlation.
  public struct SmartCardChannel: CardChannel, HeldCardChannel, @unchecked Sendable {
    /// A transport failure before the card produced a protocol response.
    public enum TransportError: Error, Equatable, Sendable {
      /// CryptoTokenKit did not complete one APDU within the response budget.
      case responseTimedOut
    }

    /// Session, response, and continuation policy chosen by the caller's transport.
    public struct WaitPolicy: Equatable, Sendable {
      /// Maximum wait for exclusive session ownership.
      public let sessionWait: DispatchTimeInterval

      /// Maximum wait for an individual APDU response.
      public let responseWait: DispatchTimeInterval

      /// How protected maximum-response signatures travel on this transport.
      public let signatureRoute: SmartCardTransmit.SignatureRoute

      /// Creates a transport wait and routing policy.
      public init(
        sessionWait: DispatchTimeInterval,
        responseWait: DispatchTimeInterval,
        signatureRoute: SmartCardTransmit.SignatureRoute
      ) {
        self.sessionWait = sessionWait
        self.responseWait = responseWait
        self.signatureRoute = signatureRoute
      }
    }

    /// Sanitized summary of one completed or timed-out APDU exchange.
    public struct ExchangeRecord: Equatable, Sendable {
      /// Formatted ``CardExchangeTrace`` line.
      public let line: String

      /// Ephemeral identifier of the channel that ran the exchange.
      public let channelID: String

      /// ``CardExchangeProgress`` timing snapshot at completion or timeout.
      public let progressSnapshot: String

      /// Creates a sanitized exchange trace record.
      public init(line: String, channelID: String, progressSnapshot: String) {
        self.line = line
        self.channelID = channelID
        self.progressSnapshot = progressSnapshot
      }
    }

    /// Optional diagnostic hooks invoked only in `DEBUG` builds.
    public struct TraceSink: Sendable {
      /// A sink that records nothing.
      public static let silent = Self(exchange: nil, trace: nil, error: nil)

      /// Receives one sanitized exchange record per APDU.
      public let exchange: (@Sendable (ExchangeRecord) -> Void)?

      /// Receives session and transport diagnostic trace lines.
      public let trace: (@Sendable (String) -> Void)?

      /// Receives transport error lines when a callback fails without a response.
      public let error: (@Sendable (String) -> Void)?

      /// Creates a diagnostic trace sink.
      @preconcurrency
      public init(
        exchange: (@Sendable (ExchangeRecord) -> Void)?,
        trace: (@Sendable (String) -> Void)?,
        error: (@Sendable (String) -> Void)?
      ) {
        self.exchange = exchange
        self.trace = trace
        self.error = error
      }
    }

    /// Carries a value across a semaphore boundary; the semaphore serializes access.
    internal final class Box<Value>: @unchecked Sendable {
      internal var value: Value

      internal init(_ value: Value) {
        self.value = value
      }
    }

    /// Shared coordination state for one in-flight APDU transmission.
    private struct PendingTransmit: @unchecked Sendable {
      let reply = Box<Data?>(nil)
      let transportError = Box<(any Error)?>(nil)
      let semaphore = DispatchSemaphore(value: 0)
      let progress = CardExchangeProgress()
    }

    /// Production ``SmartCardBacking`` forwarding directly to `TKSmartCard`.
    private final class LiveBacking: SmartCardBacking, @unchecked Sendable {
      private let smartCard: TKSmartCard

      var answerToReset: Data? {
        smartCard.slot.atr?.bytes
      }

      var isValid: Bool {
        smartCard.isValid
      }

      var slotState: TKSmartCardSlot.State {
        smartCard.slot.state
      }

      var allowedProtocols: TKSmartCardProtocol {
        get { smartCard.allowedProtocols }
        set { smartCard.allowedProtocols = newValue }
      }

      init(_ smartCard: TKSmartCard) {
        self.smartCard = smartCard
      }

      func beginSession(reply: @escaping @Sendable (Bool, (any Error)?) -> Void) {
        smartCard.beginSession(reply: reply)
      }

      func endSession() {
        smartCard.endSession()
      }

      func transmit(_ request: Data, reply: @escaping @Sendable (Data?, (any Error)?) -> Void) {
        smartCard.transmit(request, reply: reply)
      }

      func sendStructured(
        _ command: CommandApdu.StructuredCase4,
        reply: @escaping @Sendable (Data?, UInt16, (any Error)?) -> Void
      ) {
        let previousClass = smartCard.cla
        smartCard.cla = command.cla
        smartCard.send(
          ins: command.ins,
          p1: command.parameter1,
          p2: command.parameter2,
          data: command.data,
          le: command.expectedLength
        ) { [smartCard] response, statusWord, error in
          smartCard.cla = previousClass
          reply(response, statusWord, error)
        }
      }
    }

    internal let backing: any SmartCardBacking
    internal let policy: WaitPolicy
    internal let trace: TraceSink

    /// Ephemeral identifier correlating diagnostic traces for this channel instance.
    public let channelID = UUID().uuidString

    private let progressLock = NSLock()
    private let progressHolder = Box<CardExchangeProgress?>(nil)

    /// Readers return exact card bytes, permitting full plain chunks on binary reads.
    public var readChunkLength: ReadChunkLength {
      .plain
    }

    /// Answer-to-Reset bytes of the slot's card, identifying the interface without card I/O.
    public var answerToReset: Data? {
      backing.answerToReset
    }

    /// Thread-safe timing snapshot of the latest APDU exchange on this channel.
    public var exchangeProgressSnapshot: String {
      progressLock.lock()
      let progress = progressHolder.value
      progressLock.unlock()
      return progress?.snapshot() ?? "operation=none"
    }

    internal var cardHasLeft: Bool {
      !backing.isValid || backing.slotState == .missing || backing.slotState == .empty
    }

    /// Creates a channel adapting `smartCard` under `policy` and `trace`.
    public init(_ smartCard: TKSmartCard, policy: WaitPolicy, trace: TraceSink = .silent) {
      self.init(backing: LiveBacking(smartCard), policy: policy, trace: trace)
    }

    internal init(backing: any SmartCardBacking, policy: WaitPolicy, trace: TraceSink) {
      self.backing = backing
      self.policy = policy
      self.trace = trace
    }

    /// Sends one command APDU and waits synchronously for the card's response.
    public func transmit(_ payload: Data) throws -> Data {
      let pending = PendingTransmit()
      #if DEBUG
        let started = ContinuousClock.now
      #endif
      pending.progress.begin(request: payload)
      progressLock.lock()
      progressHolder.value = pending.progress
      progressLock.unlock()
      startTransmit(payload, pending: pending)
      pending.progress.submitted()
      guard pending.semaphore.wait(timeout: .now() + policy.responseWait) == .success else {
        pending.progress.timedOut()
        #if DEBUG
          recordExchange(
            request: payload,
            response: nil,
            elapsed: started.duration(to: ContinuousClock.now),
            progress: pending.progress
          )
          recordTrace("apdu: response timed out")
        #endif
        throw TransportError.responseTimedOut
      }
      #if DEBUG
        recordExchange(
          request: payload,
          response: pending.reply.value,
          elapsed: started.duration(to: ContinuousClock.now),
          progress: pending.progress
        )
      #endif
      guard let response = pending.reply.value else {
        if let callbackError = pending.transportError.value {
          #if DEBUG
            recordError("apdu: transmit failed: \(callbackError)")
          #endif
          throw callbackError
        }
        throw CardOperationError.exchangeUnanswered
      }
      return response
    }

    private func startTransmit(_ payload: Data, pending: PendingTransmit) {
      #if DEBUG
        if policy.signatureRoute == .structured,
          CommandApdu.structuredProtectedSignature(payload) != nil
        {
          recordTrace("apdu: mode=ctkContinuation channel=\(channelID)")
        }
      #endif
      SmartCardTransmit.start(
        payload,
        route: policy.signatureRoute,
        transmit: { request, completion in
          backing.transmit(request, reply: completion)
        },
        send: { command, completion in
          backing.sendStructured(command, reply: completion)
        },
        reply: { response, error in
          completeTransmit(pending, response: response, error: error)
        }
      )
    }

    private func completeTransmit(
      _ pending: PendingTransmit,
      response: Data?,
      error: (any Error)?
    ) {
      let late = pending.progress.completed()
      #if DEBUG
        if late {
          recordTrace("apdu: late callback channel=\(channelID) " + pending.progress.snapshot())
        }
        if let error {
          let failure = error as NSError
          recordTrace(
            "apdu: callback failure channel=\(channelID) "
              + "domain=\(failure.domain) code=\(failure.code) "
              + "slotState=\(backing.slotState.rawValue)"
          )
        }
      #else
        _ = late
      #endif
      pending.reply.value = response
      pending.transportError.value = error
      pending.semaphore.signal()
    }
  }
#endif
