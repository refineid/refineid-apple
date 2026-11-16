// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// Converts a card's raw ECDSA signature into X9.62 DER.
///
/// FINEID cards return an ECDSA signature as raw `r || s` (48 + 48 = 96
/// bytes for P-384; FINEID S1 v4.2 §3.8.3): two fixed-width big-endian
/// integers, no wrapper. The platform's `ecdsaSignatureDigestX962...`
/// algorithms expect the X9.62 form `SEQUENCE { INTEGER r, INTEGER s }`,
/// so the raw halves are re-encoded as DER integers here. This is the
/// one signature-shape adapter the minimal driver needs; it does no
/// cryptography.
public enum EcdsaSignature {
  /// DER tags used in the X9.62 signature structure.
  private static let sequenceTag: UInt8 = 0x30
  private static let integerTag: UInt8 = 0x02

  /// The high-bit mask that forces a leading zero on a DER integer.
  private static let highBitMask: UInt8 = 0x80

  /// The two equal halves of a raw ECDSA signature (`r` and `s`).
  private static let signatureHalves = 2

  /// Re-encodes raw `r || s` (an even-length buffer) as X9.62 DER, or
  /// nil when either coordinate is zero, empty, odd-length, or exceeds
  /// single-byte DER length framing.
  public static func derFromRawConcatenation(_ raw: Data) -> Data? {
    let bytes = Array(raw)
    guard !bytes.isEmpty, bytes.count.isMultiple(of: Self.signatureHalves) else {
      return nil
    }
    let half = bytes.count / Self.signatureHalves
    let rInteger = Self.derInteger(Array(bytes[0..<half]))
    let sInteger = Self.derInteger(Array(bytes[half..<bytes.count]))
    guard !rInteger.isEmpty, !sInteger.isEmpty else {
      return nil
    }
    var body = rInteger
    body.append(contentsOf: sInteger)
    let sequenceLength = Self.derLength(body.count)
    guard !sequenceLength.isEmpty else { return nil }
    var out: [UInt8] = [Self.sequenceTag]
    out.append(contentsOf: sequenceLength)
    out.append(contentsOf: body)
    return Data(out)
  }

  /// Re-encodes raw `r || s` of exact `coordinateOctets` width per coordinate as X9.62 DER.
  internal static func derFromRawConcatenation(_ raw: Data, coordinateOctets: Int) -> Data? {
    guard coordinateOctets > 0, raw.count == coordinateOctets * Self.signatureHalves else {
      return nil
    }
    return Self.derFromRawConcatenation(raw)
  }

  /// Encodes one non-zero big-endian magnitude as a positive DER INTEGER, or empty when invalid.
  private static func derInteger(_ magnitude: [UInt8]) -> [UInt8] {
    var value = magnitude
    while value.count > 1, value.first == 0 {
      value.removeFirst()
    }
    guard value != [.zero] else { return [] }
    if let first = value.first, first & Self.highBitMask != 0 {
      value.insert(0, at: 0)
    }
    let lengthBytes = Self.derLength(value.count)
    guard !lengthBytes.isEmpty else { return [] }
    var out: [UInt8] = [Self.integerTag]
    out.append(contentsOf: lengthBytes)
    out.append(contentsOf: value)
    return out
  }

  /// Short- or single-byte long-form DER length, or empty outside `0...255`.
  private static func derLength(_ length: Int) -> [UInt8] {
    let shortFormMaximum = 0x7F
    let oneLengthByteMarker: UInt8 = 0x81
    guard length >= 0, length <= Int(UInt8.max) else { return [] }
    if length <= shortFormMaximum {
      return [UInt8(length)]
    }
    return [oneLengthByteMarker, UInt8(length)]
  }

  /// Re-encodes an X9.62 DER signature back to raw `r || s`.
  ///
  /// XML signatures carry an ECDSA signature as the two coordinates
  /// concatenated, each left-padded to the field size of the curve the
  /// key is on - 48 octets for P-384 (RFC 4051 §2.3) - while CMS and
  /// Security.framework carry the DER form. They are not
  /// interchangeable and the difference is silent: a DER blob in an
  /// XML signature produces a well-formed document that every verifier
  /// rejects. Nil when `der` is not a two-INTEGER SEQUENCE or a
  /// coordinate does not fit in `coordinateOctets`.
  public static func rawConcatenation(
    fromDer der: Data,
    coordinateOctets: Int
  ) -> Data? {
    let bytes = Array(der)
    var offset = 0
    guard
      let sequenceLength = Self.readTag(
        Self.sequenceTag, in: bytes, at: &offset
      ),
      offset + sequenceLength == bytes.count
    else {
      return nil
    }
    var out = Data()
    for _ in 0..<Self.signatureHalves {
      guard let length = Self.readTag(Self.integerTag, in: bytes, at: &offset),
        offset + length <= bytes.count
      else {
        return nil
      }
      var magnitude = Array(bytes[offset..<offset + length])
      offset += length
      // DER INTEGERs are signed, so a coordinate whose top bit is set
      // carries a leading zero that is padding, not magnitude.
      if magnitude.first == 0, magnitude.count > 1 {
        magnitude.removeFirst()
      }
      guard magnitude.count <= coordinateOctets else { return nil }
      out.append(Data(repeating: 0, count: coordinateOctets - magnitude.count))
      out.append(Data(magnitude))
    }
    guard offset == bytes.count else { return nil }
    return out
  }

  /// Reads one expected tag and its length, advancing past both.
  ///
  /// `offset` lands on the first content byte. Nil when the tag or a
  /// well-formed length is not there.
  private static func readTag(
    _ tag: UInt8,
    in bytes: [UInt8],
    at offset: inout Int
  ) -> Int? {
    let shortFormMaximum: UInt8 = 0x7F
    let oneLengthByteMarker: UInt8 = 0x81
    guard offset < bytes.count, bytes[offset] == tag else { return nil }
    offset += 1
    guard offset < bytes.count else { return nil }
    let first = bytes[offset]
    offset += 1
    if first <= shortFormMaximum {
      return Int(first)
    }
    guard first == oneLengthByteMarker, offset < bytes.count else { return nil }
    let length = Int(bytes[offset])
    offset += 1
    return length
  }
}
