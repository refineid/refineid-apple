// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if canImport(CryptoTokenKit)
  import CryptoTokenKit
  import Foundation

  @testable import CardCore

  /// Deterministic in-memory ``SmartCardBacking`` wrapping ``StatefulSmartCardMock``.
  internal final class MockSmartCardBacking: SmartCardBacking, @unchecked Sendable {
    internal typealias BeginHandler =
      (TKSmartCardProtocol, @escaping @Sendable (Bool, (any Error)?) -> Void) -> Void
    internal typealias TransmitHandler =
      (Data, StatefulSmartCardMock, @escaping @Sendable (Data?, (any Error)?) -> Void) -> Void
    internal typealias StructuredHandler =
      (CommandApdu.StructuredCase4, @escaping @Sendable (Data?, UInt16, (any Error)?) -> Void) ->
      Void

    private let lock = NSLock()
    internal let cardMock = StatefulSmartCardMock()

    private var storedATR: Data?
    private var storedValid = true
    private var storedSlotState: TKSmartCardSlot.State = .validCard
    private var storedAllowedProtocols: TKSmartCardProtocol = .any

    private var storedOfferedProtocols: [TKSmartCardProtocol] = []
    private var storedBeginCount = 0
    private var storedEndCount = 0
    private var storedRawTransmitCount = 0
    private var storedStructuredSendCount = 0

    internal var offeredProtocols: [TKSmartCardProtocol] {
      lock.lock()
      defer { lock.unlock() }
      return storedOfferedProtocols
    }

    internal var beginCount: Int {
      lock.lock()
      defer { lock.unlock() }
      return storedBeginCount
    }

    internal var endCount: Int {
      lock.lock()
      defer { lock.unlock() }
      return storedEndCount
    }

    internal var rawTransmitCount: Int {
      lock.lock()
      defer { lock.unlock() }
      return storedRawTransmitCount
    }

    internal var structuredSendCount: Int {
      lock.lock()
      defer { lock.unlock() }
      return storedStructuredSendCount
    }

    internal var beginHandler: BeginHandler?
    internal var transmitHandler: TransmitHandler?
    internal var structuredHandler: StructuredHandler?

    internal var answerToReset: Data? {
      get {
        lock.lock()
        defer { lock.unlock() }
        return storedATR
      }
      set {
        lock.lock()
        storedATR = newValue
        lock.unlock()
      }
    }

    internal var isValid: Bool {
      get {
        lock.lock()
        defer { lock.unlock() }
        return storedValid
      }
      set {
        lock.lock()
        storedValid = newValue
        lock.unlock()
      }
    }

    internal var slotState: TKSmartCardSlot.State {
      get {
        lock.lock()
        defer { lock.unlock() }
        return storedSlotState
      }
      set {
        lock.lock()
        storedSlotState = newValue
        lock.unlock()
      }
    }

    internal var allowedProtocols: TKSmartCardProtocol {
      get {
        lock.lock()
        defer { lock.unlock() }
        return storedAllowedProtocols
      }
      set {
        lock.lock()
        storedAllowedProtocols = newValue
        lock.unlock()
      }
    }

    internal init() {
      // In-memory smart-card transport backing for unit tests.
    }

    internal func beginSession(reply: @escaping @Sendable (Bool, (any Error)?) -> Void) {
      let protocols: TKSmartCardProtocol
      let custom: BeginHandler?
      lock.lock()
      storedBeginCount += 1
      protocols = storedAllowedProtocols
      storedOfferedProtocols.append(protocols)
      custom = beginHandler
      lock.unlock()
      if let custom {
        custom(protocols, reply)
      } else {
        reply(true, nil)
      }
    }

    internal func endSession() {
      lock.lock()
      storedEndCount += 1
      lock.unlock()
    }

    internal func transmit(
      _ request: Data,
      reply: @escaping @Sendable (Data?, (any Error)?) -> Void
    ) {
      let custom: TransmitHandler?
      lock.lock()
      storedRawTransmitCount += 1
      custom = transmitHandler
      lock.unlock()
      if let custom {
        custom(request, cardMock, reply)
      } else {
        reply(cardMock.transmit(request), nil)
      }
    }

    internal func sendStructured(
      _ command: CommandApdu.StructuredCase4,
      reply: @escaping @Sendable (Data?, UInt16, (any Error)?) -> Void
    ) {
      let custom: StructuredHandler?
      lock.lock()
      storedStructuredSendCount += 1
      custom = structuredHandler
      lock.unlock()
      if let custom {
        custom(command, reply)
      } else {
        reply(cardMock.dummySignature, StatusWord.success.encoded, nil)
      }
    }
  }
#endif
