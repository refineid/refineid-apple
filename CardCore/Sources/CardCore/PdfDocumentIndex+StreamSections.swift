// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// Cross-reference streams and the object streams they index
/// (ISO 32000-1 §7.5.8, §7.5.7).
extension PdfDocumentIndex {
  /// One cross-reference stream section.
  internal static func streamSection(
    in bytes: PdfBytes,
    at start: Int
  ) throws -> Section {
    let object = try PdfStreamObject.parse(in: bytes, at: start)
    let dictionary = object.dictionary
    let widths = Self.integerArray(named: "/W", in: dictionary)
    guard
      dictionary.contains(PdfValues.xrefStreamMarker),
      widths.count == PdfValues.xrefStreamFieldCount,
      let size = Self.integer(named: "/Size", in: dictionary)
    else {
      throw PdfSigningError.structureUnreadable
    }
    var subsections = Self.integerArray(named: "/Index", in: dictionary)
    if subsections.isEmpty {
      subsections = [0, size]
    }
    let records = try Self.streamRecords(
      in: object.payload, widths: widths, subsections: subsections
    )
    return Section(records: records, trailer: dictionary, isStream: true)
  }

  /// Decodes the entry rows (ISO 32000-1 §7.5.8.3).
  private static func streamRecords(
    in payload: Data,
    widths: [Int],
    subsections: [Int]
  ) throws -> [SectionRecord] {
    let rowLength = widths.reduce(0, +)
    guard
      rowLength > 0,
      subsections.count.isMultiple(of: PdfValues.subsectionHeaderTokens)
    else {
      throw PdfSigningError.structureUnreadable
    }
    let rows = [UInt8](payload)
    var records: [SectionRecord] = []
    var cursor = 0
    for pair in stride(
      from: 0, to: subsections.count, by: PdfValues.subsectionHeaderTokens
    ) {
      let first = subsections[pair]
      for entry in 0..<subsections[pair + 1] {
        guard cursor + rowLength <= rows.count else {
          throw PdfSigningError.structureUnreadable
        }
        let fields = Self.entryFields(in: rows, at: cursor, widths: widths)
        cursor += rowLength
        records.append(Self.record(number: first + entry, fields: fields))
      }
    }
    return records
  }

  /// One row's fields, big-endian.
  ///
  /// A zero-width type field defaults to a direct entry; other absent
  /// fields default to zero.
  private static func entryFields(
    in rows: [UInt8],
    at cursor: Int,
    widths: [Int]
  ) -> [Int] {
    var fields: [Int] = []
    var offset = cursor
    for (position, width) in widths.enumerated() {
      var value = 0
      for _ in 0..<width {
        value = (value << UInt8.bitWidth) | Int(rows[offset])
        offset += 1
      }
      if position == PdfValues.entryTypeField, width == 0 {
        value = PdfValues.directEntryType
      }
      fields.append(value)
    }
    return fields
  }

  /// The record one decoded row describes.
  private static func record(number: Int, fields: [Int]) -> SectionRecord {
    switch fields[PdfValues.entryTypeField] {
    case PdfValues.directEntryType:
      return SectionRecord(
        number: number,
        location: .direct(
          offset: fields[PdfValues.entryFirstField],
          generation: fields[PdfValues.entrySecondField]
        )
      )

    case PdfValues.compressedEntryType:
      return SectionRecord(
        number: number,
        location: .compressed(
          container: fields[PdfValues.entryFirstField],
          position: fields[PdfValues.entrySecondField]
        )
      )

    default:
      // Free, and any type this reader does not know: a reference to
      // such an object is a reference to null (ISO 32000-1 §7.5.8.3),
      // so the number is claimed with no location.
      return SectionRecord(number: number, location: nil)
    }
  }

  /// The object's bytes, located through the pair table the stream
  /// opens with: `number offset` per object, offsets relative to
  /// /First.
  private static func objectSlice(
    of number: Int,
    at position: Int,
    in payload: Data,
    first: Int,
    count: Int
  ) -> String? {
    guard first <= payload.count else { return nil }
    let input = [UInt8](payload)
    let header =
      String(
        bytes: input[0..<first], encoding: .isoLatin1
      ) ?? ""
    let tokens = header.split(whereSeparator: \.isWhitespace)
    let pair = PdfValues.objectStreamPairTokens
    guard
      tokens.count >= (position + 1) * pair,
      Int(tokens[position * pair]) == number,
      let start = Int(tokens[position * pair + 1])
    else {
      return nil
    }
    let next = position + 1
    var end = payload.count
    if next < count, tokens.count >= (next + 1) * pair,
      let following = Int(tokens[next * pair + 1])
    {
      end = first + following
    }
    let bodyStart = first + start
    guard bodyStart <= end, end <= input.count else { return nil }
    return String(bytes: input[bodyStart..<end], encoding: .isoLatin1)?
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }

  /// One compressed object's body: its slice of the object stream
  /// carrying it (ISO 32000-1 §7.5.7).
  internal func compressedBody(
    of number: Int,
    container: Int,
    position: Int,
    in document: Data
  ) -> String? {
    guard case .direct(let offset, _) = locations[container] else {
      return nil
    }
    let bytes = PdfBytes(document)
    guard
      let object = try? PdfStreamObject.parse(in: bytes, at: offset),
      let first = Self.integer(
        named: PdfValues.objectStreamFirstKey, in: object.dictionary
      ),
      let count = Self.integer(
        named: PdfValues.objectStreamCountKey, in: object.dictionary
      ),
      position < count
    else {
      return nil
    }
    return Self.objectSlice(
      of: number,
      at: position,
      in: object.payload,
      first: first,
      count: count
    )
  }
}
