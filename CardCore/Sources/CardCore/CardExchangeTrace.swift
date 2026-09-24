// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// One card exchange, as the single line a trace records it on.
///
/// Traces record instruction, status and timing without card payloads.
/// Credential commands omit command sizes as well, because their size may
/// reveal the typed credential length.
public enum CardExchangeTrace {
  /// Position of the instruction byte in a command APDU: CLA INS P1 P2.
  private static let instructionIndex: Int = 1

  /// One byte as two uppercase hex digits.
  private static let byteFormat: String = "%02X"

  /// One status word as four uppercase hex digits.
  private static let wordFormat: String = "%04X"

  /// What is printed where a value could not be read.
  private static let unknown: String = "?"

  /// What is printed in place of a redacted value.
  private static let redacted: String = "redacted"

  /// One exchange as a trace line.
  ///
  /// `response` is the raw transport answer including its status word, or
  /// nil when the transport produced none at all -- a distinction worth
  /// keeping, because "the card said nothing" and "the card refused" are
  /// different faults with the same visible symptom.
  public static func line(request: Data, response: Data?, elapsed: Duration) -> String {
    let answer = response.flatMap(ResponseApdu.init(raw:))
    let status = answer.map { String(format: Self.wordFormat, $0.statusWord.encoded) }
    let tail =
      " sw=" + (status ?? Self.unknown)
      + " ms=" + TraceTiming.milliseconds(elapsed)
    let instruction = Self.instruction(of: request)
    let named =
      "apdu ins="
      + (instruction.map { byte in
        String(format: Self.byteFormat, byte)
      } ?? Self.unknown)
    guard let instruction else { return named + tail }
    guard !Self.isCredentialBearing(instruction) else {
      return named + " credential tx=" + Self.redacted + tail
    }
    let received = answer.map { String($0.payload.count) } ?? Self.unknown
    return named + " tx=\(request.count) rx=" + received + tail
  }

  /// The instruction byte, or nil when the payload is too short to have
  /// one.
  private static func instruction(of request: Data) -> UInt8? {
    let header = Array(request.prefix(Self.instructionIndex + 1))
    guard header.count > Self.instructionIndex else { return nil }
    return header[Self.instructionIndex]
  }

  /// Whether an instruction can carry a PIN, activation PIN, or PUK.
  private static func isCredentialBearing(_ instruction: UInt8) -> Bool {
    switch instruction {
    case Iso7816Values.insVerify,
      Iso7816Values.insChangeReferenceData,
      Iso7816Values.insResetRetryCounter:
      true

    default:
      false
    }
  }
}
