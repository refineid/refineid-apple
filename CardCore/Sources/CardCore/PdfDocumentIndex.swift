// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// The parts of a PDF's cross-reference chain an incremental update
/// needs (ISO 32000-1 §7.5).
///
/// Everything here counts bytes, never characters. A cross-reference
/// table addresses byte offsets, and a PDF is binary with ASCII
/// structure in it: decoding the file to a string first would be wrong
/// on any document with CRLF line endings, where `\r\n` is one Swift
/// Character but two bytes - every offset after the first line ending
/// would then be short by the number of line endings before it.
internal struct PdfDocumentIndex {
  /// Where one live object's bytes sit.
  internal enum ObjectLocation: Equatable {
    /// At a byte offset in the file, written as `N G obj`.
    case direct(offset: Int)

    /// Inside an object stream: the stream's object number and this
    /// object's position among its contents (ISO 32000-1 §7.5.7).
    case compressed(container: Int, position: Int)
  }

  /// One object a section accounts for.
  ///
  /// A free record carries no location, and claims its number so
  /// older sections' copies stay shadowed.
  internal struct SectionRecord {
    /// The object's number.
    internal let number: Int

    /// Where the object lives, or nil for a free record.
    internal let location: ObjectLocation?
  }

  /// One parsed cross-reference section.
  internal struct Section {
    /// The objects the section accounts for, in written order.
    internal let records: [SectionRecord]

    /// The trailer dictionary - for a stream section, the stream's
    /// own dictionary carries the trailer keys (ISO 32000-1 §7.5.8.2).
    internal let trailer: String

    /// Whether the section is a cross-reference stream.
    internal let isStream: Bool
  }

  /// Maximum /Prev hops followed before the chain is called broken.
  private static let maximumChainDepth = 64

  /// Object number to location, newest section winning.
  internal let locations: [Int: ObjectLocation]

  /// The newest trailer dictionary, as written.
  internal let trailer: String

  /// The offset the file's last `startxref` names.
  internal let previousStartXref: Int

  /// Whether the newest section is a stream, which decides the shape
  /// of the section an update appends: readers of such a file have
  /// already committed to following streams (ISO 32000-1 §7.5.8).
  internal let newestSectionIsStream: Bool

  /// An integer value of a trailer key, when present.
  internal static func integer(named key: String, in dictionary: String) -> Int? {
    guard let range = dictionary.range(of: key) else { return nil }
    let rest = dictionary[range.upperBound...].drop(while: \.isWhitespace)
    return Int(rest.prefix(while: \.isNumber))
  }

  /// The object number of an indirect reference value, when the key
  /// holds one.
  internal static func reference(
    named key: String,
    in dictionary: String
  ) -> Int? {
    guard let range = dictionary.range(of: key) else { return nil }
    let rest = dictionary[range.upperBound...].drop(while: \.isWhitespace)
    guard rest.first?.isNumber == true else { return nil }
    return Int(rest.prefix(while: \.isNumber))
  }

  /// The integer array value of a trailer key, empty when the key is
  /// absent or its value is not an array of unsigned decimal integers
  /// that each fit in `Int`.
  internal static func integerArray(
    named key: String,
    in dictionary: String
  ) -> [Int] {
    guard let range = dictionary.range(of: key) else { return [] }
    let rest = dictionary[range.upperBound...].drop(while: \.isWhitespace)
    guard rest.first == "[", let close = rest.firstIndex(of: "]") else {
      return []
    }
    let body = rest[rest.index(after: rest.startIndex)..<close]
    var values: [Int] = []
    for token in body.split(whereSeparator: \.isWhitespace) {
      guard token.allSatisfy({ $0.isASCII && $0.isNumber }), let value = Int(token) else {
        return []
      }
      values.append(value)
    }
    return values
  }

  /// Parses the chain from the end of the file.
  internal static func parse(_ document: Data) throws -> Self {
    let bytes = PdfBytes(document)
    guard bytes.starts(with: PdfValues.filePrefix) else {
      throw PdfSigningError.notAPdf
    }
    guard let startXref = Self.startXref(in: bytes) else {
      throw PdfSigningError.structureUnreadable
    }
    var collected: [Int: ObjectLocation] = [:]
    var claimed: Set<Int> = []
    var newestTrailer: String?
    var newestIsStream = false
    var offset: Int? = startXref
    var visited: Set<Int> = []
    var depth = 0
    while let current = offset, depth < Self.maximumChainDepth {
      guard visited.insert(current).inserted else { break }
      depth += 1
      let section = try Self.section(in: bytes, at: current)
      if newestTrailer == nil {
        newestTrailer = section.trailer
        newestIsStream = section.isStream
      }
      for record in section.records
      where claimed.insert(record.number).inserted {
        if let location = record.location {
          collected[record.number] = location
        }
      }
      offset = Self.integer(named: "/Prev", in: section.trailer)
    }
    guard let newest = newestTrailer else {
      throw PdfSigningError.structureUnreadable
    }
    guard !newest.contains(PdfValues.encryptKey) else {
      throw PdfSigningError.encrypted
    }
    return Self(
      locations: collected,
      trailer: newest,
      previousStartXref: startXref,
      newestSectionIsStream: newestIsStream
    )
  }

  /// The byte offset the last `startxref` names.
  private static func startXref(in bytes: PdfBytes) -> Int? {
    guard let found = bytes.lastRange(of: PdfValues.startXrefKeyword) else {
      return nil
    }
    return bytes.decimal(at: bytes.skippingWhitespace(from: found.upperBound))
  }

  /// One cross-reference section, whichever shape it takes: the
  /// classic table, or the stream that replaced it in PDF 1.5.
  private static func section(
    in bytes: PdfBytes,
    at offset: Int
  ) throws -> Section {
    guard offset < bytes.count else {
      throw PdfSigningError.structureUnreadable
    }
    let start = bytes.skippingWhitespace(from: offset)
    guard bytes.hasKeyword(PdfValues.xrefKeyword, at: start) else {
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
    guard
      let trailerRange = bytes.firstRange(
        of: PdfValues.trailerKeyword, from: start
      )
    else {
      throw PdfSigningError.structureUnreadable
    }
    let entriesStart = start + PdfValues.xrefKeyword.utf8.count
    var records = Self.records(
      in: bytes.text(in: entriesStart..<trailerRange.lowerBound)
    )
    guard
      let dictionary = bytes.balancedDictionary(
        from: trailerRange.upperBound
      )
    else {
      throw PdfSigningError.structureUnreadable
    }
    // A hybrid revision keeps the authoritative copy of its entries
    // in the stream its trailer names; the table is the fallback for
    // readers that predate streams (ISO 32000-1 §7.5.8.4).
    if let hybrid = Self.integer(
      named: PdfValues.hybridStreamKey, in: dictionary.text
    ) {
      let stream = try Self.streamSection(
        in: bytes, at: bytes.skippingWhitespace(from: hybrid)
      )
      records = stream.records + records
    }
    return Section(
      records: records, trailer: dictionary.text, isStream: false
    )
  }

  /// The records of one classic table section.
  ///
  /// Subsections are `first count` followed by that many
  /// `offset generation flag` triples (ISO 32000-1 §7.5.4).
  private static func records(in text: String) -> [SectionRecord] {
    var found: [SectionRecord] = []
    let tokens = text.split(whereSeparator: \.isWhitespace)
    var index = 0
    while index + PdfValues.subsectionHeaderTokens <= tokens.count,
      let first = Int(tokens[index]),
      let count = Int(tokens[index + 1])
    {
      index += PdfValues.subsectionHeaderTokens
      for entry in 0..<count
      where index + PdfValues.entryTokens <= tokens.count {
        let flag = tokens[index + PdfValues.entryFlagIndex]
        if flag == PdfValues.inUseFlag, let position = Int(tokens[index]) {
          found.append(
            SectionRecord(
              number: first + entry, location: .direct(offset: position)
            )
          )
        } else if flag == PdfValues.freeFlag {
          found.append(SectionRecord(number: first + entry, location: nil))
        }
        index += PdfValues.entryTokens
      }
    }
    return found
  }

  /// The bytes between `obj` and `endobj` at a direct offset.
  private static func directBody(at offset: Int, in document: Data) -> String? {
    guard offset < document.count else { return nil }
    let bytes = PdfBytes(document)
    guard
      let objRange = bytes.firstRange(of: "obj", from: offset),
      let endRange = bytes.firstRange(of: "endobj", from: objRange.upperBound)
    else {
      return nil
    }
    return bytes.text(in: objRange.upperBound..<endRange.lowerBound)
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }

  /// One object's body: the bytes between `obj` and `endobj`, or its
  /// slice of the object stream carrying it.
  internal func body(of number: Int, in document: Data) -> String? {
    switch locations[number] {
    case .direct(let offset):
      return Self.directBody(at: offset, in: document)

    case .compressed(let container, let position):
      return compressedBody(
        of: number, container: container, position: position, in: document
      )

    case nil:
      return nil
    }
  }
}
