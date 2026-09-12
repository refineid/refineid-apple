// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// Writing a record back to the wire, the one direction the reader in
/// `DerTlvRecord.swift` does not cover.
///
/// PACE and secure messaging build data objects as well as read them: a
/// GENERAL AUTHENTICATE body is the `7C` template carrying one context
/// data object, and a protected command body is DO'87', DO'97' and
/// DO'8E' concatenated. Nesting needs no separate entry point -- it is
/// composition: encode the inner object, then encode that as the outer
/// object's value. Encoding stays inside the definite-length,
/// single-byte-tag subset the reader accepts, so whatever this writes,
/// `sequence(in:)` reads back.
///
/// Provenance: replaces the encoding half (`encode`, `pushLength`) of
/// the RefineID iOS browser donor
/// `Sources/RefineIDBrowserKit/Card/Tlv.swift`. That donor's parsing
/// half is already covered by `DerTlvRecord.sequence(in:)` and is not
/// ported again.
extension DerTlvRecord {
  /// Long form carrying one length octet: values of 128 to 255 bytes.
  private static let singleLengthOctet: UInt8 = 1

  /// Long form carrying two length octets: values of 256 bytes and up,
  /// to the aggregate cap.
  private static let pairOfLengthOctets: UInt8 = 2

  /// This record encoded as tag, length and value, or nil when its value
  /// is longer than the reader accepts.
  public var encoded: Data? {
    Self.encoded(tag: tag, value: value)
  }

  /// A tag and value encoded as tag, length and value, or nil when the
  /// value is longer than `BinaryReadAssembler.maximumTotalLength`.
  ///
  /// The bound is the reader's own, deliberately: a builder able to emit
  /// an object this module then refuses to parse would be a trap for the
  /// caller rather than a service.
  public static func encoded(tag: UInt8, value: Data) -> Data? {
    guard let lengthOctets = Self.lengthOctets(for: value.count) else {
      return nil
    }
    return Data([tag]) + lengthOctets + value
  }

  /// The length octets for `length`, short form or bounded long form, or
  /// nil when the length exceeds the aggregate cap.
  private static func lengthOctets(for length: Int) -> Data? {
    guard length <= BinaryReadAssembler.maximumTotalLength else {
      return nil
    }
    if length < Int(Iso7816Values.derLongFormMask) {
      return Data([UInt8(truncatingIfNeeded: length)])
    }
    if length <= Int(UInt8.max) {
      return Data([
        Iso7816Values.derLongFormMask | Self.singleLengthOctet,
        UInt8(truncatingIfNeeded: length),
      ])
    }
    return Data([
      Iso7816Values.derLongFormMask | Self.pairOfLengthOctets,
      UInt8(truncatingIfNeeded: length >> Iso7816Values.byteShift),
      UInt8(truncatingIfNeeded: length),
    ])
  }
}
