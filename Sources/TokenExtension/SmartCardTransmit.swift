// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CardCore
import Foundation

/// Routes only protected maximum-response signatures through CTK continuation.
///
/// PACE, exact-length signatures, and other commands retain their wire encoding.
internal enum SmartCardTransmit {
  private static let statusWordByteShift = 8

  internal static func start(
    _ payload: Data,
    transmit: (Data, @escaping (Data?, Error?) -> Void) -> Void,
    send: (CommandApdu.StructuredCase4, @escaping (Data?, UInt16, Error?) -> Void) -> Void,
    reply: @escaping (Data?, Error?) -> Void
  ) {
    guard let command = CommandApdu.structuredProtectedSignature(payload) else {
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
