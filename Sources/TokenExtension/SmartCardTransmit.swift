// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CardCore
import Foundation

/// Routes protected maximum-response signatures on the phone's own
/// antenna through CTK continuation.
///
/// There the card answers an RSA signature in parts (`61xx`), and the slot
/// was measured going away during a separate GET RESPONSE, so CTK collects
/// the parts within one operation. A reader hands the card's whole answer
/// back in one response -- an RSA-3072 signature under secure messaging is
/// a body of about 420 bytes in one T=1 frame -- and there the command
/// goes out byte for byte, as it does for PACE, exact-length signatures
/// and every other command.
internal enum SmartCardTransmit {
  /// How a protected maximum-response signature travels.
  internal enum SignatureRoute: Sendable {
    /// As the bytes of the protected command, its answer as the card gave it.
    case raw

    /// Through CTK's structured send, which owns the continuation.
    case structured
  }

  private static let statusWordByteShift = 8

  internal static func start(
    _ payload: Data,
    route: SignatureRoute,
    transmit: (Data, @escaping @Sendable (Data?, Error?) -> Void) -> Void,
    send: (CommandApdu.StructuredCase4, @escaping @Sendable (Data?, UInt16, Error?) -> Void) ->
      Void,
    reply: @escaping @Sendable (Data?, Error?) -> Void
  ) {
    guard
      route == .structured,
      let command = CommandApdu.structuredProtectedSignature(payload)
    else {
      transmit(payload, reply)
      return
    }
    send(command) { response, statusWord, error in
      guard var response else {
        reply(nil, error)
        return
      }
      response.append(UInt8(truncatingIfNeeded: statusWord >> Self.statusWordByteShift))
      response.append(UInt8(truncatingIfNeeded: statusWord))
      reply(response, error)
    }
  }
}
