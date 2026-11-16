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
    try Self.rejectIfEncrypted(in: dictionary)
    let syntax = try PdfValidationStore.DictionarySyntax(dictionary)
    let widths = Self.integerArray(named: "/W", in: dictionary)
    guard
      PdfTypeEntry.value(of: "Type", in: dictionary)
        == PdfValues.xrefStreamMarker,
      widths.count == PdfValues.xrefStreamFieldCount,
      widths.allSatisfy({ width in
        width >= 0 && width <= PdfValues.maximumXrefFieldWidth
      }),
      let size = Self.integer(named: "/Size", in: dictionary),
      size <= PdfValues.maximumCrossReferenceEntries
    else {
      throw PdfSigningError.structureUnreadable
    }
    let subsections = try Self.streamSubsections(in: syntax, defaultSize: size)
    let records = try Self.streamRecords(
      in: object.payload, widths: widths, subsections: subsections
    )
    return Section(records: records, trailer: dictionary, isStream: true)
  }

  /// Resolves `/Index` when present, or defaults to `[0, defaultSize]`.
  private static func streamSubsections(
    in syntax: PdfValidationStore.DictionarySyntax,
    defaultSize: Int
  ) throws -> [Int] {
    guard let entry = syntax.entry(named: "Index") else {
      return [0, defaultSize]
    }
    let parsed =
      try PdfValidationStore.TypedValues.strictUnsignedIntegerArray(
        in: syntax.value(of: entry)
      )
    guard
      !parsed.isEmpty,
      parsed.count.isMultiple(of: PdfValues.subsectionHeaderTokens)
    else {
      throw PdfSigningError.structureUnreadable
    }
    return parsed
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
    var records: [SectionRecord] = []
    var cursor = payload.startIndex
    for pair in stride(
      from: 0, to: subsections.count, by: PdfValues.subsectionHeaderTokens
    ) {
      let first = subsections[pair]
      let count = subsections[pair + 1]
      guard
        first >= 0,
        count >= 0,
        count <= PdfValues.maximumCrossReferenceEntries,
        records.count <= PdfValues.maximumCrossReferenceEntries - count,
        first <= Int.max - count
      else {
        throw PdfSigningError.structureUnreadable
      }
      for entry in 0..<count {
        guard cursor <= payload.endIndex - rowLength else {
          throw PdfSigningError.structureUnreadable
        }
        let fields = try Self.entryFields(
          in: payload, at: cursor, widths: widths
        )
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
    in rows: Data,
    at cursor: Int,
    widths: [Int]
  ) throws -> [Int] {
    var fields: [Int] = []
    var offset = cursor
    for (position, width) in widths.enumerated() {
      var value = 0
      for _ in 0..<width {
        guard value <= (Int.max >> UInt8.bitWidth) else {
          throw PdfSigningError.structureUnreadable
        }
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
      return SectionRecord(number: number, location: nil)
    }
  }

  /// The object's bytes, located through the pair table the stream
  /// opens with: `number offset` per object, offsets relative to
  /// `/First`.
  private static func objectSlice(
    of number: Int,
    at position: Int,
    in payload: Data,
    first: Int,
    count: Int
  ) -> String? {
    guard first >= 0, first <= payload.count else { return nil }
    let header =
      String(
        data: payload.subdata(in: 0..<first), encoding: .isoLatin1
      ) ?? ""
    let tokens = header.split(whereSeparator: \.isWhitespace)
    let pair = PdfValues.objectStreamPairTokens
    guard
      tokens.count >= (position + 1) * pair,
      Int(tokens[position * pair]) == number,
      let start = Int(tokens[position * pair + 1]),
      start >= 0,
      start <= payload.count - first
    else {
      return nil
    }
    let next = position + 1
    var end = payload.count
    if next < count, tokens.count >= (next + 1) * pair,
      let following = Int(tokens[next * pair + 1]),
      following >= start,
      following <= payload.count - first
    {
      end = first + following
    }
    let bodyStart = first + start
    guard bodyStart <= end, end <= payload.count else { return nil }
    return String(
      data: payload.subdata(in: bodyStart..<end),
      encoding: .isoLatin1
    )?
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
    guard
      case .direct(let offset, let generation) = locations[container],
      generation == 0
    else {
      return nil
    }
    let bytes = PdfBytes(document)
    guard
      let object = try? PdfStreamObject.parse(
        in: bytes,
        at: offset,
        expectedNumber: container,
        expectedGeneration: generation
      ),
      PdfTypeEntry.value(of: "Type", in: object.dictionary) == "/ObjStm",
      let first = Self.integer(
        named: PdfValues.objectStreamFirstKey, in: object.dictionary
      ),
      let count = Self.integer(
        named: PdfValues.objectStreamCountKey, in: object.dictionary
      ),
      position >= 0,
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
