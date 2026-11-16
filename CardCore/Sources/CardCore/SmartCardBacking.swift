// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if canImport(CryptoTokenKit)
  import CryptoTokenKit
  import Foundation

  /// Underlying smart-card operations consumed by ``SmartCardChannel``.
  internal protocol SmartCardBacking: AnyObject, Sendable {
    /// Answer-to-Reset bytes reported by the slot, if any.
    var answerToReset: Data? { get }

    /// Whether the card handle remains valid in its slot.
    var isValid: Bool { get }

    /// Current state of the containing smart-card slot.
    var slotState: TKSmartCardSlot.State { get }

    /// Bitmask of card protocols offered during session establishment.
    var allowedProtocols: TKSmartCardProtocol { get set }

    /// Requests an exclusive session on the card.
    func beginSession(reply: @escaping @Sendable (Bool, (any Error)?) -> Void)

    /// Ends one reference-counted exclusive session on the card.
    func endSession()

    /// Sends one raw command APDU to the card.
    func transmit(_ request: Data, reply: @escaping @Sendable (Data?, (any Error)?) -> Void)

    /// Sends one structured Case-4 APDU through CryptoTokenKit continuation.
    func sendStructured(
      _ command: CommandApdu.StructuredCase4,
      reply: @escaping @Sendable (Data?, UInt16, (any Error)?) -> Void
    )
  }
#endif
