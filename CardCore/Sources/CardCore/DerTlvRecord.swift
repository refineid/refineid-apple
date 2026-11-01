// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// One parsed DER tag-length-value record with a single-byte tag.
///
/// The minimal reader below covers exactly what EF.TokenInfo needs:
/// sequential records, single-byte tags, short-form and bounded
/// long-form lengths, no recursion beyond the caller's own descent.
/// Malformed input yields nil, never a partial record
/// (Documentation/release-plan.md section 4.4).
///
/// The same subset is what the PACE `7C` template, its context data
/// objects and the secure-messaging data objects need, so descending
/// into a constructed record is `sequence(in: record.value)` and needs
/// no separate parser. Only a record's own bytes are handed out; a
/// record is obtained by parsing, never by assembling one from
/// unvalidated parts outside this module.
public struct DerTlvRecord: Equatable, Sendable {
  /// Thrown when the byte stream is not well-formed DER.
  public struct Malformed: Error, Equatable {}

  /// Longest long-form length encoding accepted: two length bytes,
  /// enough for the largest directly addressable card file.
  ///
  /// Deliberately narrower than ``DerReader``'s four-octet cap: that
  /// reader also parses certificates and revocation lists, while every
  /// record this parser meets is bounded by the card's addressing.
  private static let maximumLengthByteCount = 2

  /// The single-byte tag.
  public let tag: UInt8

  /// The value bytes.
  public let value: Data

  /// Parses consecutive records covering `data` exactly; throws when
  /// any record is malformed or lengths disagree with the data.
  public static func sequence(in data: Data) throws -> [Self] {
    let bytes = Array(data)
    var records: [Self] = []
    var index = 0
    while index < bytes.count {
      let parsed = try record(in: bytes, at: index)
      records.append(parsed.record)
      index = parsed.end
    }
    return records
  }

  /// Parses the one record that starts at `start`, answering it and the
  /// index just past it; throws when it is malformed or overruns `bytes`.
  internal static func record(
    in bytes: [UInt8],
    at start: Int
  ) throws -> (record: Self, end: Int) {
    var index = start
    guard index < bytes.count else { throw Malformed() }
    let recordTag = bytes[index]
    index += 1
    guard index < bytes.count else { throw Malformed() }
    let lengthByte = bytes[index]
    index += 1
    var length = Int(lengthByte)
    if lengthByte & Iso7816Values.derLongFormMask != 0 {
      let lengthByteCount = Int(lengthByte & Iso7816Values.derLengthCountMask)
      guard
        lengthByteCount >= 1,
        lengthByteCount <= Self.maximumLengthByteCount,
        index + lengthByteCount <= bytes.count
      else {
        throw Malformed()
      }
      length = 0
      for _ in 0..<lengthByteCount {
        length = length << Iso7816Values.byteShift | Int(bytes[index])
        index += 1
      }
    }
    guard
      length <= BinaryReadAssembler.maximumTotalLength,
      index + length <= bytes.count
    else {
      throw Malformed()
    }
    let record = Self(tag: recordTag, value: Data(bytes[index..<index + length]))
    return (record, index + length)
  }
}
