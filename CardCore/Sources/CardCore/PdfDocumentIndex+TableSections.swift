// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// Walking `/Prev` chains and classic `xref` table sections
/// (ISO 32000-1 §7.5.4, §7.5.5).
extension PdfDocumentIndex {
  /// Walks the `/Prev` chain from `startingAt`, failing closed on
  /// cycles, excessive depth, encryption, or invalid offsets.
  internal static func sectionsChain(
    in bytes: PdfBytes,
    startingAt: Int,
    limit: Int
  ) throws -> [Section] {
    var sections: [Section] = []
    var offset: Int? = startingAt
    var visited: Set<Int> = []
    while let current = offset {
      guard sections.count < limit, visited.insert(current).inserted else {
        throw PdfSigningError.structureUnreadable
      }
      let section = try Self.section(in: bytes, at: current)
      try Self.rejectIfEncrypted(in: section.trailer)
      sections.append(section)
      offset = try Self.previousOffset(in: section.trailer, limit: bytes.count)
    }
    return sections
  }

  /// Resolves the newest-wins live location table across `sections`.
  internal static func liveLocations(
    in sections: [Section]
  ) -> [Int: ObjectLocation] {
    var collected: [Int: ObjectLocation] = [:]
    var claimed: Set<Int> = []
    for section in sections {
      for record in section.records
      where claimed.insert(record.number).inserted {
        if let location = record.location {
          collected[record.number] = location
        }
      }
    }
    return collected
  }

  /// Collects every distinct in-use `(number, location)` across all
  /// sections from oldest to newest, grouped by object number.
  internal static func historicalRecords(
    in sections: [Section]
  ) throws -> [HistoricalObject] {
    var byNumber: [Int: [HistoricalObject]] = [:]
    var seen: Set<HistoricalObject> = []
    for section in sections.reversed() {
      for record in section.records {
        guard let location = record.location else { continue }
        let entry = HistoricalObject(number: record.number, location: location)
        guard seen.insert(entry).inserted else { continue }
        guard seen.count <= PdfValues.maximumCrossReferenceEntries else {
          throw PdfSigningError.structureUnreadable
        }
        byNumber[record.number, default: []].append(entry)
      }
    }
    return byNumber.keys.sorted().flatMap { number in
      byNumber[number] ?? []
    }
  }

  /// Reads `/Prev` when present, failing closed when it is non-integer
  /// or outside `0..<limit`.
  private static func previousOffset(
    in trailer: String,
    limit: Int
  ) throws -> Int? {
    let syntax = try PdfValidationStore.DictionarySyntax(trailer)
    guard let entry = syntax.entry(named: "Prev") else { return nil }
    guard
      let previous = PdfValidationStore.TypedValues.unsignedInteger(
        in: syntax.value(of: entry)
      ),
      previous >= 0,
      previous < limit
    else {
      throw PdfSigningError.structureUnreadable
    }
    return previous
  }

  /// One cross-reference section, whichever shape it takes: the
  /// classic table, or the stream that replaced it in PDF 1.5.
  private static func section(
    in bytes: PdfBytes,
    at offset: Int
  ) throws -> Section {
    guard offset >= 0, offset < bytes.count else {
      throw PdfSigningError.structureUnreadable
    }
    let start = bytes.skippingWhitespace(from: offset)
    guard bytes.hasKeywordToken(PdfValues.xrefKeyword, at: start) else {
      return try Self.streamSection(in: bytes, at: start)
    }
    return try Self.tableSection(in: bytes, at: start)
  }

  /// One classic table section: its records and its trailer
  /// (ISO 32000-1 §7.5.4).
  private static func tableSection(
    in bytes: PdfBytes,
    at start: Int
  ) throws -> Section {
    let entriesStart = start + PdfValues.xrefKeyword.utf8.count
    guard
      let trailerRange = bytes.keywordTokenRange(
        of: PdfValues.trailerKeyword, from: entriesStart
      ),
      let dictionary = bytes.balancedDictionary(from: trailerRange.upperBound)
    else {
      throw PdfSigningError.structureUnreadable
    }
    try Self.rejectIfEncrypted(in: dictionary.text)
    var records = try Self.records(
      in: bytes.text(in: entriesStart..<trailerRange.lowerBound)
    )
    let trailerSyntax = try PdfValidationStore.DictionarySyntax(dictionary.text)
    if trailerSyntax.entry(named: Self.normalizedKey(PdfValues.hybridStreamKey))
      != nil
    {
      guard
        let hybrid = Self.integer(
          named: PdfValues.hybridStreamKey, in: dictionary.text
        ),
        hybrid >= 0,
        hybrid < bytes.count
      else {
        throw PdfSigningError.structureUnreadable
      }
      let stream = try Self.streamSection(
        in: bytes, at: bytes.skippingWhitespace(from: hybrid)
      )
      records = stream.records + records
    }
    return Section(
      records: records, trailer: dictionary.text, isStream: false
    )
  }

  /// Parses classic `xref` subsections, failing closed on oversized or
  /// truncated entry counts.
  private static func records(in text: String) throws -> [SectionRecord] {
    let tokens = text.split(whereSeparator: \.isWhitespace)
    var found: [SectionRecord] = []
    var index = 0
    while index < tokens.count {
      guard
        index + PdfValues.subsectionHeaderTokens <= tokens.count,
        let first = Self.unsignedToken(tokens[index]),
        let count = Self.unsignedToken(tokens[index + 1]),
        count <= PdfValues.maximumCrossReferenceEntries,
        found.count <= PdfValues.maximumCrossReferenceEntries - count,
        first <= Int.max - count
      else {
        throw PdfSigningError.structureUnreadable
      }
      index += PdfValues.subsectionHeaderTokens
      guard index + count * PdfValues.entryTokens <= tokens.count else {
        throw PdfSigningError.structureUnreadable
      }
      for entry in 0..<count {
        found.append(
          try Self.tableEntry(in: tokens, at: index, number: first + entry)
        )
        index += PdfValues.entryTokens
      }
    }
    return found
  }

  /// Decodes one three-token classic `xref` entry.
  private static func tableEntry(
    in tokens: [Substring],
    at index: Int,
    number: Int
  ) throws -> SectionRecord {
    guard
      let first = Self.unsignedToken(tokens[index]),
      let generation = Self.unsignedToken(tokens[index + 1])
    else {
      throw PdfSigningError.structureUnreadable
    }
    let flag = tokens[index + PdfValues.entryFlagIndex]
    if flag == PdfValues.inUseFlag {
      return SectionRecord(
        number: number,
        location: .direct(offset: first, generation: generation)
      )
    }
    if flag == PdfValues.freeFlag {
      return SectionRecord(number: number, location: nil)
    }
    throw PdfSigningError.structureUnreadable
  }

  /// Parses an ASCII unsigned decimal token without sign characters.
  private static func unsignedToken(_ token: Substring) -> Int? {
    PdfValidationStore.ValueLexemes.unsignedInteger(Data(token.utf8))
  }
}
