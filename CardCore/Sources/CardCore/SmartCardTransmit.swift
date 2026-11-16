// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// Routes protected maximum-response signatures on the phone's built-in
/// contactless interface through CryptoTokenKit continuation.
///
/// On that interface an RSA card answers in parts (`61xx`) and the field can
/// end before a separate `GET RESPONSE` completes, so CryptoTokenKit collects
/// the parts within one structured operation. On a powered reader the card's
/// whole protected response arrives in one T=1 frame, so the command travels
/// byte for byte alongside PACE, exact-length signatures, and every other APDU.
public enum SmartCardTransmit {
  /// How a protected maximum-response signature travels.
  public enum SignatureRoute: Equatable, Sendable {
    /// As the raw bytes of the protected command, with the card's raw answer.
    case raw

    /// Through CryptoTokenKit's structured Case-4 send, which owns continuation.
    case structured
  }

  private static let statusWordByteShift = 8

  /// Dispatches one APDU through either raw transmission or structured Case-4 continuation.
  ///
  /// When CryptoTokenKit returns structured response bytes, its trailing status word is
  /// appended so callers observe a standard response APDU.
  @preconcurrency
  public static func start(
    _ payload: Data,
    route: SignatureRoute,
    transmit: (Data, @escaping @Sendable (Data?, (any Error)?) -> Void) -> Void,
    send: (
      CommandApdu.StructuredCase4,
      @escaping @Sendable (Data?, UInt16, (any Error)?) -> Void
    ) -> Void,
    reply: @escaping @Sendable (Data?, (any Error)?) -> Void
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
